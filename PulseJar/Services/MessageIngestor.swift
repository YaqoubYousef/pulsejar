import Foundation
import SwiftData
import PulseJarCore

struct IngestOutcome: Identifiable {
    enum Status {
        case recorded, needsReview, reversed, duplicate, notRecognized
    }

    let id = UUID()
    var status: Status
    var summary: String
}

/// Turns bank messages into ledger entries.
///
/// - Purchases with a known merchant and salaries are recorded directly.
/// - CliQ payments to or from people always wait for review (they may be expenses, debts or cash swaps).
/// - Reversals cancel the payment they reverse.
/// - The two messages of an internal transfer are merged into one transfer.
@MainActor
enum MessageIngestor {
    /// Seconds allowed between the two messages of one internal transfer.
    private static let transferPairingWindow: TimeInterval = 120
    /// How far back a reversal looks for the payment it reverses.
    private static let reversalWindow: TimeInterval = 3 * 24 * 3600

    static func ingest(text: String, context: ModelContext, receivedAt: Date = .now) -> IngestOutcome {
        guard let message = BankMessageParser.parse(text, receivedAt: receivedAt) else {
            return IngestOutcome(status: .notRecognized, summary: "Not a bank transaction message.")
        }
        let outcome = ingest(message, context: context)
        refreshBadge(context)
        if outcome.status == .needsReview {
            Notifier.notify(title: "Needs review", body: outcome.summary)
        }
        return outcome
    }

    static func ingestMany(text: String, context: ModelContext) -> [IngestOutcome] {
        var outcomes: [IngestOutcome] = []
        var messages: [ParsedBankMessage] = []
        for chunk in BankMessageParser.splitMessages(text) {
            if let message = BankMessageParser.parse(chunk) {
                messages.append(message)
            } else {
                let preview = chunk.replacingOccurrences(of: "\n", with: " ").prefix(40)
                outcomes.append(IngestOutcome(status: .notRecognized, summary: "Skipped: \(preview)…"))
            }
        }
        for message in messages.sorted(by: { $0.date < $1.date }) {
            outcomes.append(ingest(message, context: context))
        }
        refreshBadge(context)
        return outcomes
    }

    static func refreshBadge(_ context: ModelContext) {
        let pending = EntryStatus.needsReview.rawValue
        let count = (try? context.fetchCount(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.statusRaw == pending }))) ?? 0
        Notifier.updateBadge(count)
    }

    // MARK: - Single message

    private static func ingest(_ message: ParsedBankMessage, context: ModelContext) -> IngestOutcome {
        Seeder.seedIfNeeded(context)

        let fingerprint = message.fingerprint
        let alreadySeen = (try? context.fetchCount(FetchDescriptor<ProcessedMessage>(predicate: #Predicate { $0.fingerprint == fingerprint }))) ?? 0
        if alreadySeen > 0 {
            return IngestOutcome(status: .duplicate, summary: "Already recorded.")
        }

        let (account, isNewAccount) = resolveAccount(mask: message.account, context: context)
        let existingEntries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let amountText = message.amount.money(message.currency)

        let entry: LedgerEntry
        let status: IngestOutcome.Status
        var summary: String

        switch message.kind {
        case .purchase(let merchant):
            let category = categoryForMerchant(merchant, context: context)
            entry = newEntry(.expense, from: message, account: account, context: context)
            entry.merchant = merchant
            entry.category = category
            entry.status = category == nil ? .needsReview : .confirmed
            status = category == nil ? .needsReview : .recorded
            summary = "\(amountText) at \(merchant.capitalized)"

        case .cliqOut(let name):
            entry = newEntry(.expense, from: message, account: account, context: context)
            entry.counterparty = name
            entry.status = .needsReview
            status = .needsReview
            summary = "CliQ \(amountText) to \(name.capitalized)"

        case .cliqIn(let name):
            entry = newEntry(.income, from: message, account: account, context: context)
            entry.counterparty = name
            entry.status = .needsReview
            status = .needsReview
            summary = "CliQ \(amountText) from \(name.capitalized)"

        case .salary(let name):
            entry = newEntry(.income, from: message, account: account, context: context)
            entry.counterparty = name.isEmpty ? nil : name
            entry.category = Seeder.salaryCategory(context)
            entry.status = .confirmed
            status = .recorded
            summary = "Salary \(amountText)"

        case .reversal(let name):
            entry = newEntry(.income, from: message, account: account, context: context)
            entry.counterparty = name.isEmpty ? nil : name
            if let original = reversedPayment(for: message, name: name, account: account, in: existingEntries) {
                original.status = .reversed
                original.linkedEntryID = entry.id
                entry.linkedEntryID = original.id
                entry.status = .reversed
                entry.note = "Reversal of the payment on \(original.date.formatted(date: .abbreviated, time: .shortened))"
                status = .reversed
                summary = "Reversed payment of \(amountText) to \(name.capitalized) — both cancelled"
            } else {
                entry.status = .needsReview
                entry.note = "Reversed payment — the original payment wasn't found"
                status = .needsReview
                summary = "Reversal \(amountText) from \(name.capitalized)"
            }

        case .transferOut:
            if let half = existingEntries.first(where: { isWaitingHalf($0, for: message, missingSource: true) }) {
                entry = half
                entry.account = account
                entry.bankBalance = message.balance
                entry.status = .confirmed
                entry.note = ""
                entry.rawMessage = [entry.rawMessage, message.rawText].compactMap { $0 }.joined(separator: "\n\n")
                status = .recorded
                summary = "Transfer \(amountText) \(account.name) → \(entry.toAccount?.name ?? "?")"
            } else {
                entry = newEntry(.transfer, from: message, account: account, context: context)
                entry.status = .needsReview
                entry.note = "Transfer out — waiting for the receiving account's message"
                status = .needsReview
                summary = "Transfer \(amountText) out of \(account.name)"
            }

        case .transferIn:
            if let half = existingEntries.first(where: { isWaitingHalf($0, for: message, missingSource: false) }) {
                entry = half
                entry.toAccount = account
                entry.toBankBalance = message.balance
                entry.status = .confirmed
                entry.note = ""
                entry.rawMessage = [entry.rawMessage, message.rawText].compactMap { $0 }.joined(separator: "\n\n")
                status = .recorded
                summary = "Transfer \(amountText) \(entry.account?.name ?? "?") → \(account.name)"
            } else {
                entry = newEntry(.transfer, from: message, account: nil, context: context)
                entry.toAccount = account
                entry.toBankBalance = message.balance
                entry.status = .needsReview
                entry.note = "Transfer in — waiting for the sending account's message"
                status = .needsReview
                summary = "Transfer \(amountText) into \(account.name)"
            }

        case .unrecognized:
            entry = newEntry(.expense, from: message, account: account, context: context)
            entry.status = .needsReview
            entry.note = "Unrecognized message — check the direction and type"
            status = .needsReview
            summary = "Unrecognized message, \(amountText)"
        }

        context.insert(ProcessedMessage(fingerprint: fingerprint, rawText: message.rawText, entryID: entry.id))
        try? context.save()

        if isNewAccount, let reported = message.balance {
            let allEntries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
            account.openingBalance = 0
            account.openingBalance = reported - Ledger.balance(of: account, in: allEntries, asOf: message.date)
            try? context.save()
            summary += " (new account \(account.name))"
        }

        if status == .needsReview {
            summary += " — needs review"
        }
        return IngestOutcome(status: status, summary: summary)
    }

    // MARK: - Helpers

    private static func newEntry(_ kind: EntryKind, from message: ParsedBankMessage, account: Account?, context: ModelContext) -> LedgerEntry {
        let entry = LedgerEntry(kind: kind, amount: message.amount, date: message.date)
        context.insert(entry)
        entry.source = .bankMessage
        entry.rawMessage = message.rawText
        entry.account = account
        if account != nil {
            entry.bankBalance = message.balance
        }
        return entry
    }

    /// Finds the account for a masked number, creating it the first time it appears.
    private static func resolveAccount(mask: String?, context: ModelContext) -> (Account, Bool) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        if let mask, let match = accounts.first(where: { $0.bankMask == mask }) {
            return (match, false)
        }
        if mask == nil, let bank = accounts.first(where: { $0.kind == .bank && !$0.isArchived }) {
            return (bank, false)
        }
        let label = mask.map { "Bank \($0.prefix(4))" } ?? "Bank"
        let account = Account(name: label, kind: .bank, sortOrder: (accounts.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(account)
        account.bankMask = mask
        return (account, true)
    }

    private static func categoryForMerchant(_ merchant: String, context: ModelContext) -> EntryCategory? {
        let key = merchant.uppercased()
        let rule = try? context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.merchant == key })).first
        return rule?.category
    }

    /// The most recent outgoing payment to `name` with the same amount, shortly before the reversal.
    private static func reversedPayment(for message: ParsedBankMessage, name: String, account: Account, in entries: [LedgerEntry]) -> LedgerEntry? {
        let upperName = name.uppercased()
        return entries
            .filter { entry in
                entry.account == account
                    && entry.status != .reversed
                    && entry.amount == message.amount
                    && [.expense, .debtGiven, .transfer].contains(entry.kind)
                    && (upperName.isEmpty || (entry.counterparty ?? entry.merchant)?.uppercased() == upperName)
                    && entry.date <= message.date
                    && message.date.timeIntervalSince(entry.date) <= reversalWindow
            }
            .max(by: { $0.date < $1.date })
    }

    /// A transfer half still waiting for its other side, matching amount and time.
    private static func isWaitingHalf(_ entry: LedgerEntry, for message: ParsedBankMessage, missingSource: Bool) -> Bool {
        guard entry.kind == .transfer,
              entry.status == .needsReview,
              entry.amount == message.amount,
              abs(entry.date.timeIntervalSince(message.date)) <= transferPairingWindow
        else {
            return false
        }
        if missingSource {
            return entry.account == nil && entry.toAccount != nil
        }
        return entry.toAccount == nil && entry.account != nil
    }
}
