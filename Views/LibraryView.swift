
import SwiftUI
import UniformTypeIdentifiers

private enum LibraryLayout: String, CaseIterable {
    case grid = "Сетка"
    case list = "Список"
}

private enum ReadingFilter: String, CaseIterable {
    case all = "Все"
    case unread = "Не начаты"
    case inProgress = "Читаю"
    case completed = "Прочитаны"
}

struct LibraryView: View {
    @Binding private var requestImport: Bool

    @State private var books: [Book] = []
    @State private var searchText = ""
    @State private var selectedFormat: BookFormat?
    @State private var readingFilter: ReadingFilter = .all
    @State private var layout: LibraryLayout = .grid

    @State private var isImporterPresented = false
    @State private var errorMessage: String?
    @State private var selectedPDFBook: Book?

    private let storage = BookStorageService()

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init(requestImport: Binding<Bool> = .constant(false)) {
        self._requestImport = requestImport
    }

    private var supportedTypes: [UTType] {
        var types: [UTType] = [.pdf]

        if let epub = UTType(filenameExtension: "epub") {
            types.append(epub)
        }

        if let cbz = UTType(filenameExtension: "cbz") {
            types.append(cbz)
        }

        return types
    }

    // MARK: - Filtering

    private var displayedBooks: [Book] {
        books
            .filter { book in
                let matchesSearch =
                    searchText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    book.title.localizedCaseInsensitiveContains(
                        searchText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    )

                let matchesFormat =
                    selectedFormat == nil ||
                    book.format == selectedFormat

                let matchesReading: Bool

                switch readingFilter {
                case .all:
                    matchesReading = true

                case .unread:
                    matchesReading = book.readingProgress == 0

                case .inProgress:
                    matchesReading =
                        book.readingProgress > 0 &&
                        book.readingProgress < 1

                case .completed:
                    matchesReading = book.readingProgress >= 1
                }

                return matchesSearch &&
                    matchesFormat &&
                    matchesReading
            }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.07)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if books.isEmpty {
                        emptyLibrary
                    } else {
                        searchField

                        filters

                        if displayedBooks.isEmpty {
                            noResults
                        } else if layout == .grid {
                            gridView
                        } else {
                            listView
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if let book = selectedPDFBook {
                    PDFReaderView(book: book) {
                        selectedPDFBook = nil
                    }
                    .zIndex(1)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: requestImport) { _, shouldImport in
                guard shouldImport else { return }

                requestImport = false

                // Даём SwiftUI завершить изменение состояния,
                // прежде чем открывать системный импортёр.
                isImporterPresented = true
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: supportedTypes,
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
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

                Text("\(books.count) книг")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button {
                isImporterPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить книгу")
        }
        .padding(.bottom, 20)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.55))

            TextField(
                "",
                text: $searchText,
                prompt: Text("Поиск по названию")
                    .foregroundStyle(.white.opacity(0.45))
            )
            .foregroundStyle(.white)
            .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            .white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .padding(.bottom, 14)
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            HStack(spacing: 8) {
                Menu {
                    Picker(
                        "Статус чтения",
                        selection: $readingFilter
                    ) {
                        ForEach(ReadingFilter.allCases, id: \.self) {
                            filter in

                            Text(filter.rawValue)
                                .tag(filter)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(readingFilter.rawValue)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(
                        .white.opacity(0.08),
                        in: Capsule()
                    )
                }

                Spacer()

                Picker("Вид библиотеки", selection: $layout) {
                    Text("Сетка")
                        .tag(LibraryLayout.grid)

                    Text("Список")
                        .tag(LibraryLayout.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
        .padding(.bottom, 16)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    isSelected ? .black : .white.opacity(0.8)
                )
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.white
                                : Color.white.opacity(0.08)
                        )
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(displayedBooks) { book in
                    gridCard(book)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func gridCard(_ book: Book) -> some View {
        Button {
            openBook(book)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                BookCoverView(
                    book: book,
                    width: nil,
                    height: 220
                )
                .frame(maxWidth: .infinity)
                .clipped()

                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 36,
                        alignment: .topLeading
                    )

                HStack {
                    Text(book.format.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer()

                    Text("\(Int(book.readingProgress * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }

                ProgressView(value: book.readingProgress)
                    .tint(.white)
            }
            .padding(10)
            .background(
                .white.opacity(0.06),
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
        .contextMenu {
            Button(role: .destructive) {
                deleteBook(book)
            } label: {
                Label("Удалить книгу", systemImage: "trash")
            }
        }
    }

    // MARK: - List

    private var listView: some View {
        List {
            ForEach(displayedBooks) { book in
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
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(book.format.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))

                            ProgressView(value: book.readingProgress)
                                .tint(.white)

                            Text(progressDescription(for: book))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    Color.white.opacity(0.05)
                )
                .listRowSeparatorTint(.white.opacity(0.08))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteBook(book)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, -16)
    }

    // MARK: - Empty states

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.75))

            Text("Твоя библиотека пока пуста")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Text("Добавь PDF, EPUB или CBZ-файл,\nчтобы начать читать.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Button {
                isImporterPresented = true
            } label: {
                Label("Добавить книгу", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 38))
                .foregroundStyle(.white.opacity(0.45))

            Text("Ничего не найдено")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text("Измени запрос или параметры фильтров.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Button("Сбросить фильтры") {
                searchText = ""
                selectedFormat = nil
                readingFilter = .all
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openBook(_ book: Book) {
        switch book.format {
        case .pdf:
            selectedPDFBook = book

        case .cbz:
            // CBZ открывается через экран читалки в главном RootView.
            // Здесь пока оставляем текущую реализацию LibraryView:
            // CBZ открывается через NavigationLink в прежней версии.
            errorMessage =
                "Открой CBZ с главного экрана, чтобы продолжить чтение."

        case .epub:
            errorMessage =
                "Читалка EPUB пока находится в разработке."
        }
    }

    private func progressDescription(for book: Book) -> String {
        if book.readingProgress >= 1 {
            return "Прочитана"
        }

        if book.readingProgress > 0 {
            return "\(Int(book.readingProgress * 100))% прочитано"
        }

        return "Ещё не прочитана"
    }

    private func loadBooks() {
        do {
            books = try storage.loadLibrary()
            errorMessage = nil
        } catch {
            errorMessage =
                "Не удалось загрузить библиотеку: \(error.localizedDescription)"
        }
    }

    private func handleImport(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            var importErrors: [String] = []

            for url in urls {
                do {
                    let importedBook = try storage.importBook(from: url)

                    if !books.contains(where: {
                        $0.id == importedBook.id
                    }) {
                        books.append(importedBook)
                    }
                } catch {
                    importErrors.append(
                        "\(url.lastPathComponent): \(error.localizedDescription)"
                    )
                }
            }

            loadBooks()

            if !importErrors.isEmpty {
                errorMessage = importErrors.joined(separator: "\n")
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBook(_ book: Book) {
        do {
            try storage.deleteBook(book, from: books)
            books.removeAll { $0.id == book.id }
        } catch {
            errorMessage =
                "Не удалось удалить книгу: \(error.localizedDescription)"
        }
    }
}
