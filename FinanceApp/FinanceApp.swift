import SwiftData
import SwiftUI

@main
struct FinanceApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppDatabase.container)
    }
}

struct RootView: View {
    @Query private var entries: [LedgerEntry]

    private var pendingCount: Int {
        entries.filter { $0.status == .needsReview }.count
    }

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { EntriesView() }
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
            NavigationStack { ReviewView() }
                .tabItem { Label("Review", systemImage: "tray") }
                .badge(pendingCount)
            NavigationStack { PeopleView() }
                .tabItem { Label("People", systemImage: "person.2") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .onAppear { Notifier.requestAuthorization() }
        .onChange(of: pendingCount, initial: true) { _, count in
            Notifier.updateBadge(count)
        }
    }
}
