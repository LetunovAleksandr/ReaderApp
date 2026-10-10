
import Foundation
import UniformTypeIdentifiers

enum BookImportError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Поддерживаются только файлы EPUB, PDF и CBZ."
        }
    }
}

struct BookImportService {
    func makeBook(from url: URL) throws -> Book {
        guard let format = BookFormat(
            fileExtension: url.pathExtension
        ) else {
            throw BookImportError.unsupportedFormat
        }

        let title = url.deletingPathExtension().lastPathComponent

        return Book(
            title: title,
            fileName: url.lastPathComponent,
            format: format
        )
    }
}
