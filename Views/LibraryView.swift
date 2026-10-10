
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var isImporterPresented = false
    @State private var errorMessage: String?

    private let storage = BookStorageService()

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

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.07)
                    .ignoresSafeArea()

                if books.isEmpty {
                    emptyLibrary
                } else {
                    bookList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
                    set: { if !$0 { errorMessage = nil } }
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
    }

    private var emptyLibrary: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.8))

            Text("Твоя библиотека")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Здесь будут книги, манга и манхва")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            addButton
        }
        .padding()
    }

    private var bookList: some View {
        List {
            ForEach(books) { book in
                NavigationLink {
                    if book.format == .pdf {
                        PDFReaderView(book: book)
                    } else {
                        ContentUnavailableView(
                            "Читалка в разработке",
                            systemImage: "book.closed",
                            description: Text(
                                "Поддержка \(book.format.rawValue) появится на следующем этапе."
                            )
                        )
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 56)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(book.title)
                                .font(.headline)
                                .foregroundStyle(.white)

                            Text(book.format.rawValue)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .listRowBackground(
                    Color(red: 0.10, green: 0.10, blue: 0.11)
                )
            }
            .onDelete(perform: deleteBooks)

            Section {
                addButton
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var addButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label("Добавить книгу", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 8)
    }

    private func loadBooks() {
        do {
            books = try storage.loadLibrary()
        } catch {
            errorMessage = "Не удалось загрузить библиотеку: \(error.localizedDescription)"
        }
    }

    private func handleImport(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    let book = try storage.importBook(from: url)

                    guard !books.contains(where: { $0.id == book.id }) else {
                        continue
                    }

                    books.append(book)
                } catch {
                    errorMessage = "Не удалось импортировать файл: \(error.localizedDescription)"
                    return
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let book = books[index]

            do {
                try storage.deleteBook(book, from: books)
                books.remove(at: index)
            } catch {
                errorMessage = "Не удалось удалить книгу: \(error.localizedDescription)"
                return
            }
        }
    }
}

#Preview {
    LibraryView()
}
