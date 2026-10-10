
import SwiftUI
import ZIPFoundation
import UIKit

struct CBZReaderView: View {
    let book: Book

    @State private var pages: [URL] = []
    @State private var currentPage = 0
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
                pageReader
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            loadPages()
        }
        .onChange(of: currentPage) { _, newValue in
            saveProgress(newValue)
        }
    }

    private var pageReader: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                ForEach(
                    Array(pages.enumerated()),
                    id: \.offset
                ) { index, url in
                    GeometryReader { geometry in
                        if let image = UIImage(
                            contentsOfFile: url.path
                        ) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: geometry.size.width,
                                    height: geometry.size.height
                                )
                        } else {
                            ContentUnavailableView(
                                "Ошибка изображения",
                                systemImage: "photo"
                            )
                        }
                    }
                    .tag(index)
                    .background(Color.black)
                }
            }
            .tabViewStyle(
                .page(indexDisplayMode: .never)
            )
            .background(Color.black)

            Text("\(currentPage + 1) / \(pages.count)")
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

    private func loadPages() {
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

            try? fileManager.removeItem(
                at: extractionDirectory
            )

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

            if !extractedPages.isEmpty {
                let savedBooks = try storage.loadLibrary()

                if let savedBook = savedBooks.first(
                    where: { $0.id == book.id }
                ) {
                    currentPage = min(
                        Int(
                            (savedBook.readingProgress *
                            Double(max(pages.count - 1, 0)))
                            .rounded()
                        ),
                        max(pages.count - 1, 0)
                    )
                }
            }

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func saveProgress(_ page: Int) {
        guard !isLoading, !pages.isEmpty else {
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
                Double(page) / Double(max(pages.count - 1, 1))

            try storage.saveLibrary(books)
        } catch {
            errorMessage = "Не удалось сохранить прогресс чтения."
        }
    }
}

private enum CBZError: LocalizedError {
    case invalidArchive

    var errorDescription: String? {
        "Не удалось прочитать CBZ-архив."
    }
}
