
import Foundation
import PDFKit
import ZIPFoundation
import UIKit

struct BookStorageService {
    private let fileManager = FileManager.default

    private var rootDirectory: URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("ReaderApp", isDirectory: true)
    }

    private var booksDirectory: URL {
        rootDirectory.appendingPathComponent(
            "Books",
            isDirectory: true
        )
    }

    private var coversDirectory: URL {
        rootDirectory.appendingPathComponent(
            "Covers",
            isDirectory: true
        )
    }

    private var libraryURL: URL {
        rootDirectory.appendingPathComponent("library.json")
    }

    init() {
        try? fileManager.createDirectory(
            at: booksDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: coversDirectory,
            withIntermediateDirectories: true
        )
    }

    func fileURL(for book: Book) -> URL {
        booksDirectory.appendingPathComponent(book.fileName)
    }

    func coverURL(for book: Book) -> URL? {
        guard let coverFileName = book.coverFileName else {
            return nil
        }

        return coversDirectory.appendingPathComponent(coverFileName)
    }

    func importBook(from sourceURL: URL) throws -> Book {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let format = BookFormat(
            fileExtension: sourceURL.pathExtension
        ) else {
            throw BookImportError.unsupportedFormat
        }

        try fileManager.createDirectory(
            at: booksDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: coversDirectory,
            withIntermediateDirectories: true
        )

        let id = UUID()
        let storedFileName =
            "\(id.uuidString).\(format.rawValue.lowercased())"
        let coverFileName = "\(id.uuidString).jpg"

        let destinationURL = booksDirectory.appendingPathComponent(
            storedFileName
        )

        try fileManager.copyItem(
            at: sourceURL,
            to: destinationURL
        )

        let book = Book(
            id: id,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            fileName: storedFileName,
            format: format,
            coverFileName: coverFileName
        )

        do {
            if let coverData = generateCover(
                from: destinationURL,
                format: format
            ) {
                let coverURL = coversDirectory
                    .appendingPathComponent(coverFileName)

                try coverData.write(to: coverURL, options: .atomic)
            }

            var books = try loadLibrary()
            books.append(book)
            try saveLibrary(books)
        } catch {
            try? fileManager.removeItem(at: destinationURL)

            let coverURL = coversDirectory
                .appendingPathComponent(coverFileName)
            try? fileManager.removeItem(at: coverURL)

            throw error
        }

        return book
    }

    private func generateCover(
        from fileURL: URL,
        format: BookFormat
    ) -> Data? {
        let image: UIImage?

        switch format {
        case .pdf:
            guard let document = PDFDocument(url: fileURL),
                  let page = document.page(at: 0) else {
                return nil
            }

            image = page.thumbnail(
                of: CGSize(width: 600, height: 900),
                for: .mediaBox
            )

        case .cbz:
            image = firstImageFromCBZ(fileURL)

        case .epub:
            // Извлечение встроенной обложки EPUB добавим отдельно.
            image = nil
        }

        return image?.jpegData(compressionQuality: 0.88)
    }

    private func firstImageFromCBZ(_ archiveURL: URL) -> UIImage? {
        guard let archive = Archive(
            url: archiveURL,
            accessMode: .read
        ) else {
            return nil
        }

        let imageExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif",
            "bmp", "tif", "tiff", "webp"
        ]

        let entries = archive
            .filter { entry in
                entry.type == .file &&
                imageExtensions.contains(
                    URL(fileURLWithPath: entry.path)
                        .pathExtension.lowercased()
                )
            }
            .sorted {
                $0.path.localizedStandardCompare($1.path)
                    == .orderedAscending
            }

        guard let firstEntry = entries.first else {
            return nil
        }

        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(
                URL(fileURLWithPath: firstEntry.path).pathExtension
            )

        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        do {
            _ = try archive.extract(
                firstEntry,
                to: temporaryURL
            )

            return UIImage(contentsOfFile: temporaryURL.path)
        } catch {
            print(
                "Не удалось извлечь обложку CBZ: \(error)"
            )
            return nil
        }
    }

    func loadLibrary() throws -> [Book] {
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return []
        }

        let data = try Data(contentsOf: libraryURL)
        return try JSONDecoder().decode([Book].self, from: data)
    }

    func saveLibrary(_ books: [Book]) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(books)
        try data.write(to: libraryURL, options: .atomic)
    }

    func deleteBook(_ book: Book, from books: [Book]) throws {
        let bookURL = fileURL(for: book)

        if fileManager.fileExists(atPath: bookURL.path) {
            try fileManager.removeItem(at: bookURL)
        }

        if let coverURL = coverURL(for: book),
           fileManager.fileExists(atPath: coverURL.path) {
            try fileManager.removeItem(at: coverURL)
        }

        let updatedBooks = books.filter { $0.id != book.id }
        try saveLibrary(updatedBooks)
    }
}

enum BookImportError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Этот формат файла не поддерживается."
        }
    }
}
