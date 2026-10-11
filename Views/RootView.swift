
import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: Hashable {
    case home
    case library
    case settings
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @State private var requestImport = false
    @State private var isImporterPresented = false
    @State private var errorMessage: String?

    @State private var selectedPDFBook: Book?
    @State private var selectedCBZBook: Book?

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
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView(
                    onOpenLibrary: {
                        selectedTab = .library
                    },
                    onImportBook: {
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

                LibraryView(
                    requestImport: $requestImport
                )
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

            // PDF-читалка поверх текущей вкладки.
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
        // Запрос на импорт поступает с главного экрана
        // или из библиотеки.
        .onChange(of: requestImport) { _, shouldImport in
            guard shouldImport else { return }

            requestImport = false
            isImporterPresented = true
        }
        // Файловый менеджер находится на уровне RootView,
        // поэтому не зависит от выбранной вкладки.
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
        .fullScreenCover(item: $selectedCBZBook) { book in
            CBZReaderView(book: book)
        }
    }

    private func openBook(_ book: Book) {
        if book.format == .pdf {
            selectedPDFBook = book
        } else if book.format == .cbz {
            selectedCBZBook = book
        } else {
            errorMessage =
                "Читалка формата \(book.format.rawValue) пока находится в разработке."
        }
    }

    private func handleImport(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    _ = try storage.importBook(from: url)
                } catch {
                    errorMessage =
                        "Не удалось импортировать файл: \(error.localizedDescription)"
                    return
                }
            }

            // BookStorageService отправляет уведомление
            // об изменении библиотеки после сохранения.
            // Главный экран и библиотека обновятся автоматически.

        case .failure(let error):
            // Отмена выбора файла не считается ошибкой.
            if (error as? CocoaError)?.code != .userCancelled {
                errorMessage =
                    "Не удалось выбрать файл: \(error.localizedDescription)"
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