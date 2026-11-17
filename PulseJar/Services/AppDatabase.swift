import Foundation
import SwiftData

/// One on-device store shared by the app and the Shortcuts action.
@MainActor
enum AppDatabase {
    static let container: ModelContainer = {
        let schema = Schema([
            Account.self,
            LedgerEntry.self,
            EntryCategory.self,
            Person.self,
            MerchantRule.self,
            ProcessedMessage.self,
        ])
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
            Seeder.seedIfNeeded(container.mainContext)
            return container
        } catch {
            fatalError("Could not open the database: \(error)")
        }
    }()
}
