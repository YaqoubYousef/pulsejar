import Foundation
import SwiftData

// Amounts are stored as Int64 thousandths (fils for JOD) so they are always exact.

enum AccountKind: String, CaseIterable, Identifiable, Codable {
    case bank, cash, wallet, savings, card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .cash: return "Cash"
        case .wallet: return "E-wallet"
        case .savings: return "Savings"
        case .card: return "Card"
        }
    }

    var icon: String {
        switch self {
        case .bank: return "building.columns"
        case .cash: return "banknote"
        case .wallet: return "iphone"
        case .savings: return "archivebox"
        case .card: return "creditcard"
        }
    }
}

enum EntryKind: String, CaseIterable, Codable {
    case expense, income, transfer, debtGiven, debtReceived, adjustment

    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        case .debtGiven: return "Lent / repaid"
        case .debtReceived: return "Borrowed / got repaid"
        case .adjustment: return "Balance adjustment"
        }
    }
}

enum EntryStatus: String, Codable {
    case confirmed, needsReview, reversed
}

enum EntrySource: String, Codable {
    case manual, bankMessage
}

enum CategoryKind: String, CaseIterable, Identifiable, Codable {
    case expense, income

    var id: String { rawValue }
    var title: String { self == .expense ? "Expenses" : "Income" }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.bank.rawValue
    /// Masked number as it appears in bank messages, e.g. `1600*1380`.
    var bankMask: String?
    var currency: String = "JOD"
    var openingBalanceMinor: Int64 = 0
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \LedgerEntry.account)
    var entries: [LedgerEntry]? = []

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.toAccount)
    var incomingTransfers: [LedgerEntry]? = []

    init(name: String, kind: AccountKind, sortOrder: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .bank }
        set { kindRaw = newValue.rawValue }
    }

    var openingBalance: Decimal {
        get { Money.decimal(openingBalanceMinor) }
        set { openingBalanceMinor = Money.minor(newValue) }
    }
}

@Model
final class LedgerEntry {
    var id: UUID = UUID()
    var kindRaw: String = EntryKind.expense.rawValue
    var statusRaw: String = EntryStatus.confirmed.rawValue
    var sourceRaw: String = EntrySource.manual.rawValue
    /// Positive for every kind except `adjustment`, which is signed.
    var amountMinor: Int64 = 0
    var date: Date = Date()
    var note: String = ""
    var merchant: String?
    /// Person or company name exactly as the bank message wrote it.
    var counterparty: String?
    /// Bank-reported balance of `account` after this entry.
    var bankBalanceMinor: Int64?
    /// Bank-reported balance of `toAccount` after this entry (transfers).
    var toBankBalanceMinor: Int64?
    var rawMessage: String?
    /// For reversals: the entry on the other side of the pair.
    var linkedEntryID: UUID?
    var createdAt: Date = Date()

    var account: Account?
    var toAccount: Account?
    var category: EntryCategory?
    var person: Person?

    init(kind: EntryKind, amount: Decimal, date: Date) {
        self.kindRaw = kind.rawValue
        self.amountMinor = Money.minor(amount)
        self.date = date
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .confirmed }
        set { statusRaw = newValue.rawValue }
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { Money.decimal(amountMinor) }
        set { amountMinor = Money.minor(newValue) }
    }

    var bankBalance: Decimal? {
        get { bankBalanceMinor.map(Money.decimal) }
        set { bankBalanceMinor = newValue.map(Money.minor) }
    }

    var toBankBalance: Decimal? {
        get { toBankBalanceMinor.map(Money.decimal) }
        set { toBankBalanceMinor = newValue.map(Money.minor) }
    }
}

@Model
final class EntryCategory {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = CategoryKind.expense.rawValue
    var icon: String = "tag"
    var sortOrder: Int = 0
    /// `salary` marks the category used for salary messages.
    var systemRole: String?

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.category)
    var entries: [LedgerEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \MerchantRule.category)
    var merchantRules: [MerchantRule]? = []

    init(name: String, kind: CategoryKind, icon: String, sortOrder: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.icon = icon
        self.sortOrder = sortOrder
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    /// Name as it appears in CliQ messages, used to suggest this person.
    var bankName: String?
    var note: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.person)
    var entries: [LedgerEntry]? = []

    init(name: String) {
        self.name = name
    }
}

/// Remembers which category a merchant's purchases belong to.
@Model
final class MerchantRule {
    @Attribute(.unique) var merchant: String = ""
    var category: EntryCategory?

    init(merchant: String) {
        self.merchant = merchant
    }
}

/// Every bank message already ingested, so duplicates are ignored.
@Model
final class ProcessedMessage {
    @Attribute(.unique) var fingerprint: String = ""
    var rawText: String = ""
    var receivedAt: Date = Date()
    var entryID: UUID?

    init(fingerprint: String, rawText: String, entryID: UUID?) {
        self.fingerprint = fingerprint
        self.rawText = rawText
        self.entryID = entryID
    }
}
