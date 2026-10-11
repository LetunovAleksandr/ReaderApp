import SwiftUI

private enum AppTab: Hashable {
    case home
    case library
    case settings
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @State private var requestImport = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                onOpenLibrary: { selectedTab = .library },
                onImportBook: {
                    selectedTab = .library
                    requestImport = true
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
    }
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.045, green: 0.045, blue: 0.05)
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
