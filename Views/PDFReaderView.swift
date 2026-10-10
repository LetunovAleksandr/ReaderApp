
import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss

    @State private var document: PDFDocument?
    @State private var currentPage = 0
    @State private var loadError = false

    private let storage = BookStorageService()

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
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $currentPage) {
                    ForEach(
                        0..<document.pageCount,
                        id: \.self
                    ) { index in
                        PDFPageView(
                            page: document.page(at: index)
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
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let verticalDistance =
                            value.translation.height
                        let horizontalDistance =
                            value.translation.width

                        if verticalDistance > 120 &&
                            verticalDistance >
                            abs(horizontalDistance) * 1.3 {
                            dismiss()
                        }
                    }
            )
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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let page {
                    PDFPageRepresentable(page: page)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
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
}

private struct PDFPageRepresentable: UIViewRepresentable {
    let page: PDFPage

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = .black
        pdfView.isUserInteractionEnabled = false

        let document = PDFDocument()
        document.insert(page, at: 0)
        pdfView.document = document

        return pdfView
    }

    func updateUIView(
        _ pdfView: PDFView,
        context: Context
    ) {
        pdfView.autoScales = true
    }
}
