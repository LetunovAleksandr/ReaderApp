
import SwiftUI

struct HomeView: View {
    let onOpenLibrary: () -> Void
    let onImportBook: () -> Void
    let onOpenBook: (Book) -> Void

    @State private var books: [Book] = []
    @State private var loadError: String?

    @AppStorage("readerApp.currentBookID")
    private var currentBookID = ""

    private let storage = BookStorageService()

    // MARK: - Book selection

    private var currentBook: Book? {
        if let id = UUID(uuidString: currentBookID),
           let selectedBook = books.first(
               where: { $0.id == id }
           ) {
            return selectedBook
        }

        return books
            .filter { $0.readingProgress > 0 }
            .max { $0.dateAdded < $1.dateAdded }
    }

    private var libraryBooks: [Book] {
        let currentID = currentBook?.id

        return books
            .filter { $0.id != currentID }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("HomeLibraryBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(
                                    color: .black.opacity(0.55),
                                    location: 0
                                ),
                                .init(
                                    color: .clear,
                                    location: 0.30
                                ),
                                .init(
                                    color: .black.opacity(0.20),
                                    location: 0.58
                                ),
                                .init(
                                    color: .black.opacity(0.92),
                                    location: 1
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    Spacer(minLength: 24)

                    ScrollView(showsIndicators: false) {
                        VStack(
                            alignment: .leading,
                            spacing: 26
                        ) {
                            if books.isEmpty {
                                emptyLibrary
                            } else {
                                if let book = currentBook {
                                    currentBookSection(book)
                                }

                                if !libraryBooks.isEmpty {
                                    librarySection
                                }

                                if currentBook == nil {
                                    Button(
                                        action: onOpenLibrary
                                    ) {
                                        Label(
                                            "Открыть библиотеку",
                                            systemImage: "books.vertical"
                                        )
                                        .font(.headline)
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                        .background(
                                            .white,
                                            in: Capsule()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .task {
            loadBooks()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .readerLibraryDidChange
            )
        ) { _ in
            loadBooks()
        }
        .alert(
            "Не удалось загрузить библиотеку",
            isPresented: Binding(
                get: { loadError != nil },
                set: {
                    if !$0 {
                        loadError = nil
                    }
                }
            )
        ) {
            Button("ОК", role: .cancel) {
                loadError = nil
            }
        } message: {
            Text(loadError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(
            alignment: .center,
            spacing: 12
        ) {
            Image("ReaderAppLogo")
                .resizable()
                .scaledToFit()
                .frame(
                    maxWidth: 250,
                    maxHeight: 70
                )
                .accessibilityLabel("ReaderApp")

            Spacer(minLength: 0)

            Button(action: onImportBook) {
                Image(systemName: "plus")
                    .font(
                        .system(size: 28, weight: .regular)
                    )
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить книгу")
        }
        .padding(.top, 4)
    }

    // MARK: - Empty library

    private var emptyLibrary: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            Text("Твоя библиотека пока пуста")
                .font(
                    .system(size: 19, weight: .semibold)
                )
                .foregroundStyle(.white)

            Button(action: onImportBook) {
                Label(
                    "Добавить книгу",
                    systemImage: "plus"
                )
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    .white,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(20)
        .background(
            .black.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
    }

    // MARK: - Current book

    private func currentBookSection(
        _ book: Book
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text("Текущая книга")
                .font(
                    .system(size: 21, weight: .bold)
                )
                .foregroundStyle(.white)

            Button {
                onOpenBook(book)
            } label: {
                HStack(spacing: 16) {
                    BookCoverView(
                        book: book,
                        width: 112,
                        height: 164
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 9
                    ) {
                        Text(book.title)
                            .font(
                                .system(
                                    size: 18,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Text(book.format.rawValue)
                            .font(.system(size: 14))
                            .foregroundStyle(
                                .white.opacity(0.65)
                            )

                        Spacer(minLength: 0)

                        Text(
                            "Прогресс чтения · " +
                            "\(Int(book.readingProgress * 100))%"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(
                            .white.opacity(0.75)
                        )

                        ProgressView(
                            value: book.readingProgress
                        )
                        .tint(.white)
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .frame(height: 164)
                }
                .padding(16)
                .background(
                    .black.opacity(0.72),
                    in: RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Library carousel

    private var librarySection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text("Твоя библиотека")
                .font(
                    .system(size: 21, weight: .bold)
                )
                .foregroundStyle(.white)

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(
                    alignment: .top,
                    spacing: 14
                ) {
                    ForEach(libraryBooks) { book in
                        libraryCard(book)
                    }
                }
            }
        }
    }

    private func libraryCard(
        _ book: Book
    ) -> some View {
        Button {
            onOpenBook(book)
        } label: {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                BookCoverView(
                    book: book,
                    width: 132,
                    height: 176
                )

                Text(book.title)
                    .font(
                        .system(size: 14, weight: .semibold)
                    )
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(
                        width: 132,
                        alignment: .leading
                    )

                if book.readingProgress > 0 {
                    ProgressView(
                        value: book.readingProgress
                    )
                    .tint(.white)
                    .frame(width: 132)

                    Text(
                        "\(Int(book.readingProgress * 100))% прочитано"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(
                        .white.opacity(0.7)
                    )
                } else {
                    Text("Ещё не прочитана")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            .white.opacity(0.65)
                        )
                }
            }
            .padding(10)
            .background(
                .black.opacity(0.55),
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Book format icon

    private func bookFormatIcon(
        _ book: Book,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.10))

            Image(
                systemName: book.format == .cbz
                    ? "photo.on.rectangle.angled"
                    : "doc.richtext"
            )
            .font(.system(size: 30))
            .foregroundStyle(
                .white.opacity(0.85)
            )
        }
        .frame(
            width: width,
            height: height
        )
    }

    // MARK: - Data

    private func loadBooks() {
        do {
            books = try storage.loadLibrary()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview {
    HomeView(
        onOpenLibrary: {},
        onImportBook: {},
        onOpenBook: { _ in }
    )
}
