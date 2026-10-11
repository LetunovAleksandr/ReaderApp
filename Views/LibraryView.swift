
import SwiftUI
import UniformTypeIdentifiers

private enum LibraryLayout: String, CaseIterable {
    case grid = "Сетка"
    case list = "Список"
}

private enum ReadingFilter: String, CaseIterable {
    case all = "Все"
    case unread = "Не начато"
    case inProgress = "Читаю"
    case completed = "Прочитано"
}

struct LibraryView: View {
    @Binding private var requestImport: Bool

    @State private var books: [Book] = []
    @State private var searchText = ""
    @State private var selectedFormat: BookFormat?
    @State private var readingFilter: ReadingFilter = .all
    @State private var layout: LibraryLayout = .grid
    @State private var errorMessage: String?
    @State private var selectedPDFBook: Book?

    private let storage = BookStorageService()

    private let gridSpacing: CGFloat = 16
    private let cardPadding: CGFloat = 8
    private let coverHeight: CGFloat = 190

    init(requestImport: Binding<Bool> = .constant(false)) {
        self._requestImport = requestImport
    }

    private var displayedBooks: [Book] {
        books
            .filter { book in
                searchText.isEmpty ||
                book.title.localizedCaseInsensitiveContains(searchText)
            }
            .filter { book in
                selectedFormat == nil || book.format == selectedFormat
            }
            .filter { book in
                switch readingFilter {
                case .all:
                    return true
                case .unread:
                    return book.readingProgress <= 0
                case .inProgress:
                    return book.readingProgress > 0 &&
                        book.readingProgress < 1
                case .completed:
                    return book.readingProgress >= 1
                }
            }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(
                    red: 0.06,
                    green: 0.06,
                    blue: 0.07
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if books.isEmpty {
                        emptyLibrary
                    } else {
                        searchAndFilters

                        if displayedBooks.isEmpty {
                            noResults
                        } else {
                            switch layout {
                            case .grid:
                                gridView
                            case .list:
                                listView
                            }
                        }
                    }
                }
            }
            .overlay {
                if let book = selectedPDFBook {
                    PDFReaderView(book: book) {
                        selectedPDFBook = nil
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .zIndex(1)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("ОК", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Библиотека")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text(bookCountDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button {
                requestImport = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить книгу")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private var bookCountDescription: String {
        let count = books.count

        switch count % 10 {
        case 1 where count % 100 != 11:
            return "\(count) книга"
        case 2...4 where !(12...14).contains(count % 100):
            return "\(count) книги"
        default:
            return "\(count) книг"
        }
    }

    // MARK: - Search and filters

    private var searchAndFilters: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))

                TextField("Поиск по библиотеке", text: $searchText)
                    .font(.subheadline)
                    .tint(.white)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.white.opacity(0.07))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    formatChip(title: "Все форматы", format: nil)

                    ForEach(BookFormat.allCases, id: \.self) { format in
                        formatChip(
                            title: format.rawValue,
                            format: format
                        )
                    }
                }
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(ReadingFilter.allCases, id: \.self) { filter in
                        Button {
                            readingFilter = filter
                        } label: {
                            if readingFilter == filter {
                                Label(
                                    filter.rawValue,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(filter.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(readingFilter.rawValue)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.white.opacity(0.07))
                    .clipShape(Capsule())
                }

                Spacer()

                Picker("Вид библиотеки", selection: $layout) {
                    Text("Сетка").tag(LibraryLayout.grid)
                    Text("Список").tag(LibraryLayout.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func formatChip(
        title: String,
        format: BookFormat?
    ) -> some View {
        let isSelected = selectedFormat == format

        return Button {
            selectedFormat = format
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    isSelected ? .black : .white.opacity(0.8)
                )
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    isSelected ? Color.white : Color.white.opacity(0.07)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var gridView: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let cardWidth = max(
                0,
                (availableWidth - gridSpacing) / 2
            )
            let coverWidth = max(
                0,
                cardWidth - cardPadding * 2
            )

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .fixed(cardWidth),
                            spacing: gridSpacing,
                            alignment: .top
                        ),
                        GridItem(
                            .fixed(cardWidth),
                            spacing: gridSpacing,
                            alignment: .top
                        )
                    ],
                    alignment: .center,
                    spacing: 18
                ) {
                    ForEach(displayedBooks) { book in
                        gridCard(
                            book,
                            cardWidth: cardWidth,
                            coverWidth: coverWidth
                        )
                    }
                }
                .frame(
                    width: availableWidth,
                    alignment: .top
                )
                .padding(.bottom, 24)
            }
        }
    }

    private func gridCard(
        _ book: Book,
        cardWidth: CGFloat,
        coverWidth: CGFloat
    ) -> some View {
        Button {
            openBook(book)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                BookCoverView(
                    book: book,
                    width: coverWidth,
                    height: coverHeight
                )
                .overlay(alignment: .bottomLeading) {
                    Text(book.format.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.65))
                        .clipShape(Capsule())
                        .padding(8)
                }

                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 36,
                        alignment: .topLeading
                    )

                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: book.readingProgress)
                        .tint(.white.opacity(0.85))

                    Text(progressDescription(for: book))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(cardPadding)
            .frame(width: cardWidth, alignment: .topLeading)
            .background(.white.opacity(0.045))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteBook(book)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    // MARK: - List

    private var listView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(displayedBooks) { book in
                    listRow(book)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func listRow(_ book: Book) -> some View {
        Button {
            openBook(book)
        } label: {
            HStack(spacing: 14) {
                BookCoverView(
                    book: book,
                    width: 66,
                    height: 92
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(book.format.rawValue)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 0)

                    ProgressView(value: book.readingProgress)
                        .tint(.white.opacity(0.85))

                    Text(progressDescription(for: book))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 92)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(12)
            .background(.white.opacity(0.045))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteBook(book)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty states

    private var emptyLibrary: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.65))

            Text("Твоя библиотека пока пуста")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("Добавь книгу, чтобы она появилась здесь.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Button {
                requestImport = true
            } label: {
                Label("Добавить книгу", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.5))

            Text("Ничего не найдено")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Измени запрос или параметры фильтрации.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Button("Сбросить фильтры") {
                searchText = ""
                selectedFormat = nil
                readingFilter = .all
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.top, 4)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func progressDescription(for book: Book) -> String {
        let percent = Int(
            (book.readingProgress * 100).rounded()
        )

        if percent <= 0 {
            return "Не начато"
        }

        if percent >= 100 {
            return "Прочитано"
        }

        return "Прочитано \(percent)%"
    }

    private func openBook(_ book: Book) {
        switch book.format {
        case .pdf:
            selectedPDFBook = book

        case .cbz:
            errorMessage =
                "Открой CBZ с главного экрана, чтобы продолжить чтение."

        case .epub:
            errorMessage =
                "Читалка формата EPUB пока находится в разработке."
        }
    }

    private func loadBooks() {
        do {
            books = try storage.loadLibrary()
        } catch {
            errorMessage =
                "Не удалось загрузить библиотеку: \(error.localizedDescription)"
        }
    }

    private func deleteBook(_ book: Book) {
        do {
            try storage.deleteBook(book, from: books)
            loadBooks()
        } catch {
            errorMessage =
                "Не удалось удалить книгу: \(error.localizedDescription)"
        }
    }
}

#Preview {
    LibraryView()
}
