
import SwiftUI
import PDFKit
import UIKit

struct PDFReaderView: View {
    let book: Book

    @State private var document: PDFDocument?
    @State private var currentPage = 0
    @State private var loadError = false

    private let storage = BookStorageService()

    private let enhancementSettings = ImageEnhancementSettings(
        enabled: true,
        contrast: 1.2,
        brightness: 0.02,
        saturation: 0.0,
        sharpness: 0.4
    )

    var body: some View {
        Group {
            if let document {
                pageReader(document)
            } else if loadError {
                ContentUnavailableView(
                    "Не удалось открыть PDF",
                    systemImage: "doc.text",
                    description: Text("Файл не найден или повреждён.")
                )
            } else {
                ProgressView("Открываем книгу…")
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            loadDocument()
        }
        .task(id: currentPage) {
            await preloadNearbyPages()
        }
        .onChange(of: currentPage) { _, newValue in
            saveProgress(newValue)
        }
    }

    private func pageReader(_ document: PDFDocument) -> some View {
        SwipeToDismissContainer {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    TabView(selection: $currentPage) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            PDFPageView(
                                document: document,
                                bookID: book.id,
                                pageIndex: index,
                                settings: enhancementSettings,
                                availableSize: geometry.size
                            )
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )

                    VStack {
                        Spacer()

                        Text("\(currentPage + 1) / \(document.pageCount)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(.bottom, 12)
                            .allowsHitTesting(false)
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
            }
            .ignoresSafeArea()
        }
    }

    private func loadDocument() {
        guard document == nil, !loadError else { return }

        let url = storage.fileURL(for: book)

        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
            loadError = true
            return
        }

        var restoredPage = 0

        do {
            let books = try storage.loadLibrary()

            if let savedBook = books.first(where: { $0.id == book.id }) {
                restoredPage = Int(
                    (
                        savedBook.readingProgress *
                        Double(max(pdf.pageCount - 1, 0))
                    ).rounded()
                )
            }
        } catch {
            restoredPage = 0
        }

        currentPage = min(max(restoredPage, 0), pdf.pageCount - 1)
        document = pdf
    }

    private func preloadNearbyPages() async {
        guard let document, document.pageCount > 0 else { return }

        // Ближайшая страница подготавливается первой.
        let indices = [
            currentPage + 1,
            currentPage - 1,
            currentPage + 2,
            currentPage - 2
        ]

        for index in indices {
            guard !Task.isCancelled else { return }
            guard (0..<document.pageCount).contains(index) else { continue }

            guard let page = document.page(at: index) else { continue }

            let key = cacheKey(pageIndex: index)
            let settings = enhancementSettings

            if ImageEnhancementService.shared.cachedImage(
                for: key,
                settings: settings
            ) != nil {
                continue
            }

            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            let size = Self.renderSize(for: bounds)

            // Рендеринг и фильтры выполняются вне основного потока.
            _ = await Task.detached(priority: .utility) {
                PDFPageRenderer.render(
                    page: page,
                    size: size,
                    cacheKey: key,
                    settings: settings
                )
            }.value
        }
    }

    private func cacheKey(pageIndex: Int) -> String {
        "pdf-\(book.id.uuidString)-page-\(pageIndex)-1400"
    }

    private static func renderSize(for bounds: CGRect) -> CGSize {
        let maxDimension: CGFloat = 1400
        let aspectRatio = bounds.width / bounds.height

        if aspectRatio >= 1 {
            return CGSize(
                width: maxDimension,
                height: max(1, maxDimension / aspectRatio)
            )
        }

        return CGSize(
            width: max(1, maxDimension * aspectRatio),
            height: maxDimension
        )
    }

    private func saveProgress(_ page: Int) {
        guard let document, document.pageCount > 0 else { return }

        do {
            var books = try storage.loadLibrary()

            guard let index = books.firstIndex(where: { $0.id == book.id }) else {
                return
            }

            books[index].readingProgress =
                Double(page) / Double(max(document.pageCount - 1, 1))

            try storage.saveLibrary(books)
        } catch {
            print("Не удалось сохранить прогресс PDF: \(error)")
        }
    }
}

private struct PDFPageView: View {
    let document: PDFDocument
    let bookID: UUID
    let pageIndex: Int
    let settings: ImageEnhancementSettings
    let availableSize: CGSize

    @State private var renderedImage: UIImage?
    @State private var isRendering = false

    var body: some View {
        ZStack {
            Color.black

            if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: availableSize.width,
                        height: availableSize.height
                    )
            } else if isRendering {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(
            width: availableSize.width,
            height: availableSize.height
        )
        .task(id: pageIndex) {
            await renderPageIfNeeded()
        }
    }

    @MainActor
    private func renderPageIfNeeded() async {
        guard !isRendering, renderedImage == nil else { return }

        let key = "pdf-\(bookID.uuidString)-page-\(pageIndex)-1400"

        if let cached = ImageEnhancementService.shared.cachedImage(
            for: key,
            settings: settings
        ) {
            renderedImage = cached
            return
        }

        guard let page = document.page(at: pageIndex) else { return }

        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let aspectRatio = bounds.width / bounds.height
        let maxDimension: CGFloat = 1400

        let size: CGSize
        if aspectRatio >= 1 {
            size = CGSize(
                width: maxDimension,
                height: max(1, maxDimension / aspectRatio)
            )
        } else {
            size = CGSize(
                width: max(1, maxDimension * aspectRatio),
                height: maxDimension
            )
        }

        isRendering = true
        defer { isRendering = false }

        let settings = settings

        let image = await Task.detached(priority: .userInitiated) {
            PDFPageRenderer.render(
                page: page,
                size: size,
                cacheKey: key,
                settings: settings
            )
        }.value

        guard !Task.isCancelled else { return }
        renderedImage = image
    }
}

private enum PDFPageRenderer {
    nonisolated static func render(
        page: PDFPage,
        size: CGSize,
        cacheKey: String,
        settings: ImageEnhancementSettings
    ) -> UIImage? {
        if let cached = ImageEnhancementService.shared.cachedImage(
            for: cacheKey,
            settings: settings
        ) {
            return cached
        }

        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)

        let originalImage = renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))

            let context = rendererContext.cgContext
            context.saveGState()

            context.translateBy(x: 0, y: size.height)
            context.scaleBy(
                x: size.width / bounds.width,
                y: -size.height / bounds.height
            )
            context.translateBy(x: -bounds.minX, y: -bounds.minY)

            page.draw(with: .mediaBox, to: context)

            context.restoreGState()
        }

        return ImageEnhancementService.shared.enhance(
            originalImage,
            cacheKey: cacheKey,
            settings: settings
        )
    }
}
