
import SwiftUI

private enum AppTab: Hashable {
    case home
    case library
    case settings
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @State private var requestImport = false
    @State private var selectedBook: Book?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                onOpenLibrary: {
                    selectedTab = .library
                },
                onImportBook: {
                    selectedTab = .library
                    requestImport = true
                },
                onOpenBook: { book in
                    selectedBook = book
                }
            )
            .tabItem {
                Label("Главная", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            LibraryView(requestImport: $requestImport)
                .tabItem {
                    Label("Библиотека", systemImage: "books.vertical")
                }
                .tag(AppTab.library)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedBook) { book in
            if book.format == .pdf {
                PDFReaderView(book: book) {
                    selectedBook = nil
                }
            } else if book.format == .cbz {
                CBZReaderView(book: book)
            } else {
                ContentUnavailableView(
                    "Формат не поддерживается",
                    systemImage: "book.closed",
                    description: Text(
                        "Не удалось открыть выбранную книгу."
                    )
                )
            }
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(
                    red: 0.045,
                    green: 0.045,
                    blue: 0.05
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))

                    Text("Настройки")
                        .font(.title2.bold())

                    Text("Настройки приложения появятся здесь.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}