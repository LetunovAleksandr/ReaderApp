
import SwiftUI
import ZIPFoundation
import UIKit

struct CBZReaderView: View {
    let book: Book

    @State private var pages: [URL] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let storage = BookStorageService()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загружаем страницы…")
                    .tint(.white)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Не удалось открыть мангу",
                    systemImage: "archivebox",
                    description: Text(errorMessage)
                )
            } else if pages.isEmpty {
                ContentUnavailableView(
                    "Нет страниц",
                    systemImage: "photo",
                    description: Text(
                        "В архиве не найдены изображения страниц."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(
                            Array(pages.enumerated()),
                            id: \.offset
                        ) { _, url in
                            if let uiImage = UIImage(
                                contentsOfFile: url.path
                            ) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .background(Color.black)
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadPages()
        }
    }

    private func loadPages() {
        guard isLoading else { return }

        do {
            let archiveURL = storage.fileURL(for: book)

            let fileManager = FileManager.default
            let cacheDirectory = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )[0]

            let extractionDirectory = cacheDirectory
                .appendingPathComponent(
                    "CBZ-\(book.id.uuidString)",
                    isDirectory: true
                )

            try? fileManager.removeItem(at: extractionDirectory)

            try fileManager.createDirectory(
                at: extractionDirectory,
                withIntermediateDirectories: true
            )

            guard let archive = Archive(
                url: archiveURL,
                accessMode: .read
            ) else {
                throw CBZError.invalidArchive
            }

            let imageExtensions: Set<String> = [
                "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff"
            ]

            let entries = archive.filter { entry in
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

            var extractedPages: [URL] = []

            for (index, entry) in entries.enumerated() {
                let originalName = URL(
                    fileURLWithPath: entry.path
                ).lastPathComponent

                let destination = extractionDirectory
                    .appendingPathComponent(
                        "\(index)-\(originalName)"
                    )

                _ = try archive.extract(
                    entry,
                    to: destination
                )

                extractedPages.append(destination)
            }

            pages = extractedPages
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private enum CBZError: LocalizedError {
    case invalidArchive

    var errorDescription: String? {
        "Файл не удалось прочитать как CBZ-архив."
    }
}

#Preview {
    NavigationStack {
        CBZReaderView(
            book: Book(
                title: "Пример манги",
                fileName: "example.cbz",
                format: .cbz
            )
        )
    }
    .preferredColorScheme(.dark)
}
