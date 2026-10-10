
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
                SwipeToDismissContainer {
                    pageReader(document)
                }
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
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $currentPage) {
                    ForEach(
                        0..<document.pageCount,
                        id: \.self
                    ) { index in
                        PDFPageView(
                            page: document.page(at: index),
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

        document = pdf

        do {
            let books = try storage.loadLibrary()

            if let savedBook = books.first(
                where: { $0.id == book.id }
            ) {
                currentPage = min(
                    Int(
                        (
                            savedBook.readingProgress *
                            Double(max(pdf.pageCount - 1, 0))
                        ).rounded()
                    ),
                    pdf.pageCount - 1
                )
            }
        } catch {
            currentPage = 0
        }
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
    let page: PDFPage?
    let settings: ImageEnhancementSettings

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let page {
                    enhancedPage(
                        page,
                        size: geometry.size
                    )
                } else {
                    ContentUnavailableView(
                        "Страница недоступна",
                        systemImage: "doc.text"
                    )
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
    }

    @ViewBuilder
    private func enhancedPage(
        _ page: PDFPage,
        size: CGSize
    ) -> some View {
        let pageBounds = page.bounds(for: .mediaBox)
        let pageAspectRatio = pageBounds.width / max(pageBounds.height, 1)
        let screenAspectRatio = size.width / max(size.height, 1)

        let renderSize: CGSize = {
            if pageAspectRatio > screenAspectRatio {
                return CGSize(
                    width: 1800,
                    height: max(1, 1800 / pageAspectRatio)
                )
            } else {
                return CGSize(
                    width: max(1, 1800 * pageAspectRatio),
                    height: 1800
                )
            }
        }()

        if let image = renderPDFPage(
            page,
            size: renderSize
        ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(
                    width: size.width,
                    height: size.height
                )
        } else {
            ContentUnavailableView(
                "Не удалось обработать страницу",
                systemImage: "doc.text"
            )
        }
    }

    private func renderPDFPage(
        _ page: PDFPage,
        size: CGSize
    ) -> UIImage? {
        let pageBounds = page.bounds(for: .mediaBox)

        let renderer = UIGraphicsImageRenderer(size: size)

        let originalImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.saveGState()

            context.cgContext.translateBy(
                x: 0,
                y: size.height
            )

            context.cgContext.scaleBy(
                x: size.width / pageBounds.width,
                y: -size.height / pageBounds.height
            )

            context.cgContext.translateBy(
                x: -pageBounds.minX,
                y: -pageBounds.minY
            )

            page.draw(
                with: .mediaBox,
                to: context.cgContext
            )

            context.cgContext.restoreGState()
        }

        return ImageEnhancementService.shared.enhance(
            originalImage,
            settings: settings
        )
    }
}
