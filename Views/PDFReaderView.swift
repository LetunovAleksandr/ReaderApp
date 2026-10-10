
import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let book: Book

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
        .background(Color.black)
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
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                ForEach(
                    0..<document.pageCount,
                    id: \.self
                ) { index in
                    PDFPageView(
                        page: document.page(at: index)
                    )
                    .tag(index)
                    .background(Color.black)
                }
            }
            .tabViewStyle(
                .page(indexDisplayMode: .never)
            )

            Text(
                "\(min(currentPage + 1, document.pageCount)) / \(document.pageCount)"
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
    }

    private func loadDocument() {
        guard document == nil, !loadError else {
            return
        }

        let url = storage.fileURL(for: book)

        guard let pdf = PDFDocument(url: url),
              pdf.pageCount > 0 else {
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
                        (savedBook.readingProgress *
                        Double(max(pdf.pageCount - 1, 0)))
                        .rounded()
                    ),
                    pdf.pageCount - 1
                )
            }
        } catch {
            currentPage = 0
        }
    }

    private func saveProgress(_ page: Int) {
        guard let document,
              document.pageCount > 0 else {
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
            print("Не удалось сохранить прогресс PDF: \(error)")
        }
    }
}

private struct PDFPageView: View {
    let page: PDFPage?

    var body: some View {
        GeometryReader { geometry in
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
    }
}

private struct PDFPageRepresentable: UIViewRepresentable {
    let page: PDFPage

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.document = PDFDocument()
        view.document?.insert(page, at: 0)
        return view
    }

    func updateUIView(
        _ view: PDFView,
        context: Context
    ) {
        if view.document?.page(at: 0) !== page {
            let document = PDFDocument()
            document.insert(page, at: 0)
            view.document = document
        }

        view.autoScales = true
    }
}
