import Foundation
import SwiftData

/// One-tap answers for an entry waiting in Review.
///
/// Each answer does what the full editor would do for the same choice, keeping the bank-reported
/// balances attached to the right account.
@MainActor
enum ReviewResolver {
    enum Answer: Identifiable {
        /// The person sent you money: they paid you back, or lent you money.
        case debtIn(person: Person?, name: String)
        /// You sent money to the person: you lent it, or paid them back.
        case debtOut(person: Person?, name: String)
        /// The CliQ came in and you handed over cash (Cash → bank).
        case cashSwapIn(cash: Account)
        /// You sent CliQ and got cash back (bank → Cash).
        case cashSwapOut(cash: Account)
        case income(EntryCategory)
        case expense(EntryCategory, rememberMerchant: Bool)

        var id: String {
            switch self {
            case .debtIn: return "debtIn"
            case .debtOut: return "debtOut"
            case .cashSwapIn: return "cashSwapIn"
            case .cashSwapOut: return "cashSwapOut"
            case .income(let category): return "income-\(category.id)"
            case .expense(let category, _): return "expense-\(category.id)"
            }
        }
    }

    /// The kind of question a pending entry raises.
    enum Question {
        /// CliQ received from a named person.
        case cliqIn(name: String)
        /// CliQ sent to a named person.
        case cliqOut(name: String)
        /// A card purchase whose merchant has no category yet.
        case purchase(merchant: String)
        /// Anything else (unmatched transfer halves, unknown messages): only the full editor can answer.
        case other
    }

    static func question(for entry: LedgerEntry) -> Question {
        guard entry.account != nil, entry.linkedEntryID == nil else {
            return .other
        }
        if let merchant = entry.merchant, entry.kind == .expense {
            return .purchase(merchant: merchant)
        }
        if let name = entry.counterparty, entry.note.isEmpty {
            switch entry.kind {
            case .income: return .cliqIn(name: name)
            case .expense: return .cliqOut(name: name)
            default: return .other
            }
        }
        return .other
    }

    /// The person whose bank name matches the message, if any.
    static func matchingPerson(for counterparty: String, in people: [Person]) -> Person? {
        let key = counterparty.uppercased()
        return people.first { $0.bankName?.uppercased() == key }
            ?? people.first { $0.name.uppercased() == key }
    }

    static func apply(_ answer: Answer, to entry: LedgerEntry, context: ModelContext) {
        guard let bank = entry.account else {
            return
        }
        let reported = entry.bankBalance

        entry.category = nil
        entry.person = nil
        entry.toAccount = nil
        entry.toBankBalance = nil

        switch answer {
        case .debtIn(let person, let name):
            entry.kind = .debtReceived
            entry.person = resolve(person, name: name, counterparty: entry.counterparty, context: context)
        case .debtOut(let person, let name):
            entry.kind = .debtGiven
            entry.person = resolve(person, name: name, counterparty: entry.counterparty, context: context)
        case .cashSwapIn(let cash):
            entry.kind = .transfer
            entry.account = cash
            entry.bankBalance = nil
            entry.toAccount = bank
            entry.toBankBalance = reported
        case .cashSwapOut(let cash):
            entry.kind = .transfer
            entry.toAccount = cash
        case .income(let category):
            entry.kind = .income
            entry.category = category
        case .expense(let category, let remember):
            entry.kind = .expense
            entry.category = category
            if remember, let merchant = entry.merchant {
                Ledger.rememberMerchant(merchant, category: category, context: context)
            }
        }

        entry.status = .confirmed
        try? context.save()
        MessageIngestor.refreshBadge(context)
    }

    private static func resolve(_ person: Person?, name: String, counterparty: String?, context: ModelContext) -> Person {
        if let person {
            if person.bankName == nil, let counterparty {
                person.bankName = counterparty.uppercased()
            }
            return person
        }
        let newPerson = Person(name: name)
        context.insert(newPerson)
        newPerson.bankName = counterparty?.uppercased()
        return newPerson
    }
}
