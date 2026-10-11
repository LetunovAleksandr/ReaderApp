
import Foundation
import PDFKit
import ZIPFoundation
import UIKit
import CryptoKit

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

    // MARK: - Import

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

        let sourceHash = try calculateSHA256(of: sourceURL)

        var books = try loadLibrary()

        // Проверяем дубликаты до копирования файла.
        for index in books.indices {
            let existingBook = books[index]

            let existingURL = fileURL(for: existingBook)

            guard fileManager.fileExists(
                atPath: existingURL.path
            ) else {
                continue
            }

            let existingHash: String

            if let savedHash = existingBook.contentHash {
                existingHash = savedHash
            } else {
                existingHash = try calculateSHA256(
                    of: existingURL
                )

                // Запоминаем хеш для будущих проверок.
                books[index].contentHash = existingHash
            }

            if existingHash == sourceHash {
                // Не создаём дубликат и сохраняем прогресс.
                if books[index].contentHash == nil {
                    books[index].contentHash = existingHash
                    try saveLibrary(books)
                }

                return books[index]
            }
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
            coverFileName: coverFileName,
            contentHash: sourceHash
        )

        do {
            if let coverData = generateCover(
                from: destinationURL,
                format: format
            ) {
                let coverURL = coversDirectory
                    .appendingPathComponent(coverFileName)

                try coverData.write(
                    to: coverURL,
                    options: .atomic
                )
            }

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

    // MARK: - SHA-256

    private func calculateSHA256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)

        return digest.map {
            String(format: "%02x", $0)
        }.joined()
    }

    // MARK: - Covers

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
            // Извлечение встроенной обложки EPUB пока не реализовано.
            image = nil
        }

        return image?.jpegData(compressionQuality: 0.88)
    }

    private func firstImageFromCBZ(
        _ archiveURL: URL
    ) -> UIImage? {
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
            print("Не удалось извлечь обложку CBZ: \(error)")
            return nil
        }
    }

    // MARK: - Library

    func loadLibrary() throws -> [Book] {
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return []
        }

        let data = try Data(contentsOf: libraryURL)

        return try JSONDecoder().decode(
            [Book].self,
            from: data
        )
    }

    func saveLibrary(_ books: [Book]) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(books)

        try data.write(
            to: libraryURL,
            options: .atomic
        )

        NotificationCenter.default.post(
            name: .readerLibraryDidChange,
            object: nil
        )
    }

    // MARK: - Delete

    func deleteBook(
        _ book: Book,
        from books: [Book]
    ) throws {
        let bookURL = fileURL(for: book)

        if fileManager.fileExists(atPath: bookURL.path) {
            try fileManager.removeItem(at: bookURL)
        }

        if let coverURL = coverURL(for: book),
           fileManager.fileExists(atPath: coverURL.path) {
            try fileManager.removeItem(at: coverURL)
        }

        let updatedBooks = books.filter {
            $0.id != book.id
        }

        try saveLibrary(updatedBooks)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let readerLibraryDidChange =
        Notification.Name("readerLibraryDidChange")
}
