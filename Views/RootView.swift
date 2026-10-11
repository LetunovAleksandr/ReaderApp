
import SwiftUI

private enum AppTab: Hashable {
    case home
    case library
    case settings
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @State private var requestImport = false

    @State private var selectedPDFBook: Book?
    @State private var selectedCBZBook: Book?

    var body: some View {
        ZStack {
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
                        openBook(book)
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

            // PDF располагается поверх основного интерфейса.
            // Под ним остаётся видимым выбранный экран приложения.
            if let book = selectedPDFBook {
                PDFReaderView(book: book) {
                    selectedPDFBook = nil
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(Color.clear)
                .transition(.identity)
                .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedCBZBook) { book in
            CBZReaderView(book: book)
        }
    }

    private func openBook(_ book: Book) {
        if book.format == .pdf {
            selectedPDFBook = book
        } else if book.format == .cbz {
            selectedCBZBook = book
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