
import Foundation

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

    private var libraryURL: URL {
        rootDirectory.appendingPathComponent("library.json")
    }

    func fileURL(for book: Book) -> URL {
        booksDirectory.appendingPathComponent(book.fileName)
    }


    init() {
        try? fileManager.createDirectory(
            at: booksDirectory,
            withIntermediateDirectories: true
        )
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

        let id = UUID()
        let storedFileName = "\(id.uuidString).\(format.rawValue.lowercased())"
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
            format: format
        )

        do {
            var books = try loadLibrary()
            books.append(book)
            try saveLibrary(books)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        return book
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
        let fileURL = booksDirectory.appendingPathComponent(book.fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        let updatedBooks = books.filter { $0.id != book.id }
        try saveLibrary(updatedBooks)
    }
}
