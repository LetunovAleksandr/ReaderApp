
import SwiftUI
import PDFKit
import UIKit

struct PDFReaderView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss

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
                    description: Text(
                        "Файл не найден или повреждён."
                    )
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
        .onChange(of: currentPage) { _, newValue in
            saveProgress(newValue)
        }
    }

    private func pageReader(
        _ document: PDFDocument
    ) -> some View {
        SwipeToDismissContainer {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    TabView(selection: $currentPage) {
                        ForEach(
                            0..<document.pageCount,
                            id: \.self
                        ) { index in
                            PDFPageView(
                                document: document,
                                bookID: book.id,
                                pageIndex: index,
                                settings: enhancementSettings
                            )
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(
                        .page(indexDisplayMode: .never)
                    )
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )

                    VStack {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(
                                        .system(
                                            size: 18,
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.75))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }

                        Spacer()

                        Text(
                            "\(currentPage + 1) / \(document.pageCount)"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                        .allowsHitTesting(false)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
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
        guard document == nil, !loadError else {
            return
        }

        let url = storage.fileURL(for: book)

        guard
            let pdf = PDFDocument(url: url),
            pdf.pageCount > 0
        else {
            loadError = true
            return
        }

        do {
            let books = try storage.loadLibrary()

            if let savedBook = books.first(
                where: { $0.id == book.id }
            ) {
                let lastPage = pdf.pageCount - 1

                currentPage = min(
                    max(
                        Int(
                            (
                                savedBook.readingProgress *
                                Double(lastPage)
                            ).rounded()
                        ),
                        0
                    ),
                    lastPage
                )
            }
        } catch {
            currentPage = 0
        }

        document = pdf
    }

    private func saveProgress(_ page: Int) {
        guard
            let document,
            document.pageCount > 0
        else {
            return
        }

        do {
            var books = try storage.loadLibrary()

            guard let index = books.firstIndex(
                where: { $0.id == book.id }
            ) else {
                return
            }

            books[index].readingProgress =
                Double(page) /
                Double(max(document.pageCount - 1, 1))

            try storage.saveLibrary(books)
        } catch {
            print(
                "Не удалось сохранить прогресс PDF: \(error)"
            )
        }
    }
}

private struct PDFPageView: View {
    let document: PDFDocument
    let bookID: UUID
    let pageIndex: Int
    let settings: ImageEnhancementSettings

    @State private var renderedImage: UIImage?
    @State private var isRendering = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let renderedImage {
                    Image(uiImage: renderedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                } else if isRendering {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .task(id: pageIndex) {
                await renderPageIfNeeded()
            }
        }
    }

    @MainActor
    private func renderPageIfNeeded() async {
        guard !isRendering, renderedImage == nil else {
            return
        }

        let maxDimension: CGFloat = 1400

        let cacheKey =
            "pdf-\(bookID.uuidString)-page-\(pageIndex)-\(Int(maxDimension))"

        if let cached = ImageEnhancementService.shared.cachedImage(
            for: cacheKey,
            settings: settings
        ) {
            renderedImage = cached
            return
        }

        guard let page = document.page(at: pageIndex) else {
            return
        }

        isRendering = true
        defer {
            isRendering = false
        }

        // Даём интерфейсу возможность показать индикатор загрузки.
        await Task.yield()

        guard !Task.isCancelled else {
            return
        }

        let bounds = page.bounds(for: .mediaBox)

        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let aspectRatio = bounds.width / bounds.height

        let renderSize: CGSize
        if aspectRatio >= 1 {
            renderSize = CGSize(
                width: maxDimension,
                height: max(1, maxDimension / aspectRatio)
            )
        } else {
            renderSize = CGSize(
                width: max(1, maxDimension * aspectRatio),
                height: maxDimension
            )
        }

        let renderer = UIGraphicsImageRenderer(size: renderSize)

        let originalImage = renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(
                CGRect(origin: .zero, size: renderSize)
            )

            let context = rendererContext.cgContext
            context.saveGState()

            context.translateBy(
                x: 0,
                y: renderSize.height
            )
            context.scaleBy(
                x: renderSize.width / bounds.width,
                y: -renderSize.height / bounds.height
            )
            context.translateBy(
                x: -bounds.minX,
                y: -bounds.minY
            )

            page.draw(with: .mediaBox, to: context)

            context.restoreGState()
        }

        guard !Task.isCancelled else {
            return
        }

        let enhancedImage = ImageEnhancementService.shared.enhance(
            originalImage,
            cacheKey: cacheKey,
            settings: settings
        )

        guard !Task.isCancelled else {
            return
        }

        renderedImage = enhancedImage
    }
}
