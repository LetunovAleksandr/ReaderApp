
import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let book: Book

    @State private var document: PDFDocument?
    @State private var loadError = false

    private let storage = BookStorageService()

    var body: some View {
        Group {
            if let document {
                PDFDocumentView(document: document)
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
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard document == nil, !loadError else {
                return
            }

            let url = storage.fileURL(for: book)
            document = PDFDocument(url: url)

            if document == nil {
                loadError = true
            }
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()

        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(
            red: 0.06,
            green: 0.06,
            blue: 0.07,
            alpha: 1
        )

        return pdfView
    }

    func updateUIView(
        _ pdfView: PDFView,
        context: Context
    ) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        pdfView.autoScales = true
    }
}
