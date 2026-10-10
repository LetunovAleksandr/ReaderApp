
import Foundation

enum BookFormat: String, Codable, CaseIterable {
    case epub = "EPUB"
    case pdf = "PDF"
    case cbz = "CBZ"

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "epub":
            self = .epub
        case "pdf":
            self = .pdf
        case "cbz":
            self = .cbz
        default:
            return nil
        }
    }
}

struct Book: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var fileName: String
    var format: BookFormat
    var dateAdded: Date
    var readingProgress: Double

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        format: BookFormat,
        dateAdded: Date = Date(),
        readingProgress: Double = 0
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.format = format
        self.dateAdded = dateAdded
        self.readingProgress = min(max(readingProgress, 0), 1)
    }
}
