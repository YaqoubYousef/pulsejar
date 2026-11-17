import Foundation
import SwiftData

@MainActor
enum Seeder {
    private static let seededKey = "didSeedDefaults"
    static let salaryRole = "salary"

    /// Adds default categories and a Cash account once, on first launch.
    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else {
            return
        }

        let expenses: [(String, String)] = [
            ("Food & Dining", "fork.knife"),
            ("Groceries", "cart"),
            ("Transport", "car"),
            ("Fuel", "fuelpump"),
            ("Bills & Utilities", "bolt"),
            ("Phone & Internet", "wifi"),
            ("Shopping", "bag"),
            ("Health", "cross.case"),
            ("Entertainment", "gamecontroller"),
            ("Education", "book"),
            ("Gifts & Donations", "gift"),
            ("Bank Fees", "building.columns"),
            ("Other", "ellipsis.circle"),
        ]
        let incomes: [(String, String)] = [
            ("Salary", "briefcase"),
            ("Freelance", "laptopcomputer"),
            ("Gifts", "gift"),
            ("Refunds", "arrow.uturn.backward"),
            ("Other", "ellipsis.circle"),
        ]

        for (index, item) in expenses.enumerated() {
            context.insert(EntryCategory(name: item.0, kind: .expense, icon: item.1, sortOrder: index))
        }
        for (index, item) in incomes.enumerated() {
            let category = EntryCategory(name: item.0, kind: .income, icon: item.1, sortOrder: index)
            if index == 0 {
                category.systemRole = salaryRole
            }
            context.insert(category)
        }
        context.insert(Account(name: "Cash", kind: .cash, sortOrder: 0))

        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    static func salaryCategory(_ context: ModelContext) -> EntryCategory? {
        let categories = (try? context.fetch(FetchDescriptor<EntryCategory>())) ?? []
        return categories.first { $0.systemRole == salaryRole }
            ?? categories.first { $0.kind == .income && $0.name.localizedCaseInsensitiveContains("salary") }
    }
}
