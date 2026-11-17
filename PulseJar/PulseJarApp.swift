import SwiftData
import SwiftUI

@main
struct PulseJarApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchContainer()
        }
        .modelContainer(AppDatabase.container)
    }
}

/// Shows the splash with the maker's seal briefly, then fades into the app.
struct LaunchContainer: View {
    @State private var showsSplash = true

    var body: some View {
        ZStack {
            RootView()
            if showsSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.4)) {
                showsSplash = false
            }
        }
    }
}

struct RootView: View {
    @Query private var entries: [LedgerEntry]
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .dark

    private var pendingCount: Int {
        entries.filter { $0.status == .needsReview }.count
    }

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { EntriesView() }
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
                .badge(pendingCount)
            NavigationStack { PeopleView() }
                .tabItem { Label("People", systemImage: "person.2") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(Theme.accent)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            Notifier.requestAuthorization()
            KeyboardDismissal.install()
        }
        .onChange(of: pendingCount, initial: true) { _, count in
            Notifier.updateBadge(count)
        }
    }
}
