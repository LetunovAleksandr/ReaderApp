import SwiftUI

struct HomeView: View {
    let onOpenLibrary: () -> Void
    let onImportBook: () -> Void

    @State private var books: [Book] = []
    @State private var loadError: String?

    private let storage = BookStorageService()

    private var currentBook: Book? {
        books.max { $0.dateAdded < $1.dateAdded }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("HomeLibraryBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.55), location: 0),
                                .init(color: .clear, location: 0.30),
                                .init(color: .black.opacity(0.20), location: 0.58),
                                .init(color: .black.opacity(0.92), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 20)
                    homeActions
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task{
            loadBooks()
        }
        .alert("Не удалось загрузить библиотеку", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("ОК", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image("ReaderAppLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 250, maxHeight: 70, alignment: .leading)
                .accessibilityLabel("ReaderApp")

            Spacer(minLength: 0)

            Button(action: onImportBook) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить книгу")
        }
        .padding(.top, 4)
    }

    private var homeActions: some View {
        VStack(spacing: 16) {
            Button(action: onOpenLibrary) {
                HStack(spacing: 14) {
                    Image(systemName: "book")
                        .font(.system(size: 27, weight: .medium))
                    Text("Продолжить чтение")
                        .font(.system(size: 19, weight: .semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 19, weight: .medium))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(minHeight: 72)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)

            currentBookCard
        }
    }

    @ViewBuilder
    private var currentBookCard: some View {
        if let book = currentBook {
            Button(action: onOpenLibrary) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Текущая книга")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                            Image(systemName: book.format == .cbz ? "photo.on.rectangle.angled" : "doc.richtext")
                                .font(.system(size: 29))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: 78, height: 108)

                        VStack(alignment: .leading, spacing: 9) {
                            Text(book.title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(book.format.rawValue)
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.62))

                            Text("Прогресс чтения · \(Int(book.readingProgress * 100))%")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.72))

                            ProgressView(value: book.readingProgress)
                                .tint(.white)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Твоя библиотека пока пуста")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Добавь PDF или CBZ, чтобы начать чтение.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                Button(action: onImportBook) {
                    Label("Добавить книгу", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func loadBooks() {
        do {
            books = try storage.loadLibrary()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview {
    HomeView(onOpenLibrary: {}, onImportBook: {})
}
