import Foundation
import SwiftData
import SwiftUI

struct BankBalanceMismatch {
    var bankBalance: Decimal
    var appBalance: Decimal
    var date: Date
}

enum Ledger {
    /// Opening balance plus every entry's effect, optionally only up to `date`.
    static func balance(of account: Account, in entries: [LedgerEntry], asOf date: Date? = nil) -> Decimal {
        entries.reduce(account.openingBalance) { total, entry in
            if let date, entry.date > date {
                return total
            }
            return total + entry.effect(on: account)
        }
    }

    /// The latest balance the bank reported for this account.
    static func latestBankBalance(of account: Account, in entries: [LedgerEntry]) -> (date: Date, balance: Decimal)? {
        var latest: (date: Date, balance: Decimal)?
        for entry in entries {
            var reported: Decimal?
            if entry.account == account {
                reported = entry.bankBalance
            }
            if entry.toAccount == account, let toBalance = entry.toBankBalance {
                reported = toBalance
            }
            guard let reported else {
                continue
            }
            if latest == nil || entry.date >= latest!.date {
                latest = (entry.date, reported)
            }
        }
        return latest
    }

    /// Non-nil when the app's balance differs from what the bank last reported.
    static func mismatch(for account: Account, in entries: [LedgerEntry]) -> BankBalanceMismatch? {
        guard let snapshot = latestBankBalance(of: account, in: entries) else {
            return nil
        }
        let appBalance = balance(of: account, in: entries, asOf: snapshot.date)
        guard appBalance != snapshot.balance else {
            return nil
        }
        return BankBalanceMismatch(bankBalance: snapshot.balance, appBalance: appBalance, date: snapshot.date)
    }

    /// Positive: the person owes you. Negative: you owe them.
    static func debtBalance(of person: Person, in entries: [LedgerEntry]) -> Decimal {
        entries.reduce(Decimal(0)) { total, entry in
            guard entry.person == person, entry.status != .reversed else {
                return total
            }
            switch entry.kind {
            case .debtGiven: return total + entry.amount
            case .debtReceived: return total - entry.amount
            default: return total
            }
        }
    }

    static func debtDescription(_ balance: Decimal, name: String) -> String {
        if balance > 0 {
            return "\(name) owes you \(balance.money())"
        }
        if balance < 0 {
            return "You owe \(name) \((-balance).money())"
        }
        return "Settled"
    }

    static func debtColor(_ balance: Decimal) -> Color {
        balance > 0 ? .green : balance < 0 ? .red : .secondary
    }

    /// Deletes an entry, its reversal partner, and the records that would block re-importing its message.
    @MainActor
    static func delete(_ entry: LedgerEntry, context: ModelContext) {
        var ids: Set<UUID> = [entry.id]
        if let linkedID = entry.linkedEntryID,
           let linked = try? context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == linkedID })).first {
            ids.insert(linked.id)
            context.delete(linked)
        }
        let processed = (try? context.fetch(FetchDescriptor<ProcessedMessage>())) ?? []
        for record in processed {
            if let entryID = record.entryID, ids.contains(entryID) {
                context.delete(record)
            }
        }
        context.delete(entry)
        try? context.save()
        MessageIngestor.refreshBadge(context)
    }

    /// Saves a merchant → category rule and applies it to that merchant's purchases still waiting for review.
    @MainActor
    static func rememberMerchant(_ merchant: String, category: EntryCategory, context: ModelContext) {
        let key = merchant.uppercased()
        if let rule = try? context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.merchant == key })).first {
            rule.category = category
        } else {
            let rule = MerchantRule(merchant: key)
            context.insert(rule)
            rule.category = category
        }

        let pending = EntryStatus.needsReview.rawValue
        let waiting = (try? context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.statusRaw == pending }))) ?? []
        for entry in waiting where entry.kind == .expense && entry.merchant?.uppercased() == key {
            entry.category = category
            entry.status = .confirmed
        }
    }
}

extension LedgerEntry {
    /// How much this entry changes `account`'s balance. Reversed entries change nothing.
    func effect(on account: Account) -> Decimal {
        guard status != .reversed else {
            return 0
        }
        return signedAmount(for: account)
    }

    /// Signed amount from `account`'s point of view, ignoring status.
    func signedAmount(for account: Account) -> Decimal {
        var change: Decimal = 0
        if self.account == account {
            switch kind {
            case .expense, .debtGiven, .transfer: change -= amount
            case .income, .debtReceived, .adjustment: change += amount
            }
        }
        if kind == .transfer, toAccount == account {
            change += amount
        }
        return change
    }

    /// Signed amount without an account in mind. Transfers stay positive.
    var signedAmount: Decimal {
        switch kind {
        case .expense, .debtGiven: return -amount
        case .income, .debtReceived, .adjustment, .transfer: return amount
        }
    }

    var displayTitle: String {
        switch kind {
        case .transfer:
            return "\(account?.name ?? "?") → \(toAccount?.name ?? "?")"
        case .debtGiven, .debtReceived:
            if let person {
                return person.name
            }
        case .adjustment:
            return "Balance adjustment"
        case .expense, .income:
            break
        }
        if let name = merchant ?? counterparty {
            return name.capitalized
        }
        if !note.isEmpty {
            return note
        }
        return category?.name ?? kind.title
    }

    var subtitle: String {
        var parts: [String] = []
        switch kind {
        case .transfer:
            if let counterparty {
                parts.append(counterparty.capitalized)
            }
        case .debtGiven, .debtReceived:
            parts.append(kind.title)
            if let account {
                parts.append(account.name)
            }
        default:
            parts.append(category?.name ?? (status == .needsReview ? "Not categorized" : kind.title))
            if let account {
                parts.append(account.name)
            }
        }
        parts.append(date.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: " · ")
    }

    var iconName: String {
        if let category, kind == .expense || kind == .income {
            return category.icon
        }
        switch kind {
        case .expense: return "cart"
        case .income: return "arrow.down.circle"
        case .transfer: return "arrow.left.arrow.right"
        case .debtGiven: return "person.crop.circle.badge.minus"
        case .debtReceived: return "person.crop.circle.badge.plus"
        case .adjustment: return "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch kind {
        case .expense: return .red
        case .income: return .green
        case .transfer: return .blue
        case .debtGiven, .debtReceived: return .purple
        case .adjustment: return .gray
        }
    }

    var searchText: String {
        [merchant, counterparty, note, category?.name, person?.name, account?.name, toAccount?.name]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}
