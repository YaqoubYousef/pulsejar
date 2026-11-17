import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupFile: Codable {
    struct AccountRecord: Codable {
        var id: UUID
        var name: String
        var kind: String
        var bankMask: String?
        var currency: String
        var openingBalanceMinor: Int64
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
    }

    struct CategoryRecord: Codable {
        var id: UUID
        var name: String
        var kind: String
        var icon: String
        var sortOrder: Int
        var systemRole: String?
    }

    struct PersonRecord: Codable {
        var id: UUID
        var name: String
        var bankName: String?
        var note: String
        var createdAt: Date
    }

    struct EntryRecord: Codable {
        var id: UUID
        var kind: String
        var status: String
        var source: String
        var amountMinor: Int64
        var date: Date
        var note: String
        var merchant: String?
        var counterparty: String?
        var bankBalanceMinor: Int64?
        var toBankBalanceMinor: Int64?
        var rawMessage: String?
        var linkedEntryID: UUID?
        var createdAt: Date
        var accountID: UUID?
        var toAccountID: UUID?
        var categoryID: UUID?
        var personID: UUID?
    }

    struct MerchantRuleRecord: Codable {
        var merchant: String
        var categoryID: UUID?
    }

    struct ProcessedRecord: Codable {
        var fingerprint: String
        var rawText: String
        var receivedAt: Date
        var entryID: UUID?
    }

    var version = 1
    var exportedAt: Date
    var accounts: [AccountRecord]
    var categories: [CategoryRecord]
    var people: [PersonRecord]
    var entries: [EntryRecord]
    var merchantRules: [MerchantRuleRecord]
    var processedMessages: [ProcessedRecord]
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
enum Backup {
    static func export(context: ModelContext) throws -> Data {
        let file = BackupFile(
            exportedAt: .now,
            accounts: try context.fetch(FetchDescriptor<Account>()).map {
                .init(id: $0.id, name: $0.name, kind: $0.kindRaw, bankMask: $0.bankMask, currency: $0.currency,
                      openingBalanceMinor: $0.openingBalanceMinor, sortOrder: $0.sortOrder, isArchived: $0.isArchived, createdAt: $0.createdAt)
            },
            categories: try context.fetch(FetchDescriptor<EntryCategory>()).map {
                .init(id: $0.id, name: $0.name, kind: $0.kindRaw, icon: $0.icon, sortOrder: $0.sortOrder, systemRole: $0.systemRole)
            },
            people: try context.fetch(FetchDescriptor<Person>()).map {
                .init(id: $0.id, name: $0.name, bankName: $0.bankName, note: $0.note, createdAt: $0.createdAt)
            },
            entries: try context.fetch(FetchDescriptor<LedgerEntry>()).map {
                .init(id: $0.id, kind: $0.kindRaw, status: $0.statusRaw, source: $0.sourceRaw, amountMinor: $0.amountMinor,
                      date: $0.date, note: $0.note, merchant: $0.merchant, counterparty: $0.counterparty,
                      bankBalanceMinor: $0.bankBalanceMinor, toBankBalanceMinor: $0.toBankBalanceMinor, rawMessage: $0.rawMessage,
                      linkedEntryID: $0.linkedEntryID, createdAt: $0.createdAt, accountID: $0.account?.id, toAccountID: $0.toAccount?.id,
                      categoryID: $0.category?.id, personID: $0.person?.id)
            },
            merchantRules: try context.fetch(FetchDescriptor<MerchantRule>()).map {
                .init(merchant: $0.merchant, categoryID: $0.category?.id)
            },
            processedMessages: try context.fetch(FetchDescriptor<ProcessedMessage>()).map {
                .init(fingerprint: $0.fingerprint, rawText: $0.rawText, receivedAt: $0.receivedAt, entryID: $0.entryID)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// Deletes everything and loads the backup.
    static func restore(_ file: BackupFile, context: ModelContext) throws {
        for entry in try context.fetch(FetchDescriptor<LedgerEntry>()) { context.delete(entry) }
        for rule in try context.fetch(FetchDescriptor<MerchantRule>()) { context.delete(rule) }
        for record in try context.fetch(FetchDescriptor<ProcessedMessage>()) { context.delete(record) }
        for person in try context.fetch(FetchDescriptor<Person>()) { context.delete(person) }
        for category in try context.fetch(FetchDescriptor<EntryCategory>()) { context.delete(category) }
        for account in try context.fetch(FetchDescriptor<Account>()) { context.delete(account) }
        try context.save()

        var accounts: [UUID: Account] = [:]
        for record in file.accounts {
            let account = Account(name: record.name, kind: AccountKind(rawValue: record.kind) ?? .bank, sortOrder: record.sortOrder)
            context.insert(account)
            account.id = record.id
            account.bankMask = record.bankMask
            account.currency = record.currency
            account.openingBalanceMinor = record.openingBalanceMinor
            account.isArchived = record.isArchived
            account.createdAt = record.createdAt
            accounts[record.id] = account
        }

        var categories: [UUID: EntryCategory] = [:]
        for record in file.categories {
            let category = EntryCategory(name: record.name, kind: CategoryKind(rawValue: record.kind) ?? .expense, icon: record.icon, sortOrder: record.sortOrder)
            context.insert(category)
            category.id = record.id
            category.systemRole = record.systemRole
            categories[record.id] = category
        }

        var people: [UUID: Person] = [:]
        for record in file.people {
            let person = Person(name: record.name)
            context.insert(person)
            person.id = record.id
            person.bankName = record.bankName
            person.note = record.note
            person.createdAt = record.createdAt
            people[record.id] = person
        }

        for record in file.entries {
            let entry = LedgerEntry(kind: .expense, amount: 0, date: record.date)
            context.insert(entry)
            entry.id = record.id
            entry.kindRaw = record.kind
            entry.statusRaw = record.status
            entry.sourceRaw = record.source
            entry.amountMinor = record.amountMinor
            entry.note = record.note
            entry.merchant = record.merchant
            entry.counterparty = record.counterparty
            entry.bankBalanceMinor = record.bankBalanceMinor
            entry.toBankBalanceMinor = record.toBankBalanceMinor
            entry.rawMessage = record.rawMessage
            entry.linkedEntryID = record.linkedEntryID
            entry.createdAt = record.createdAt
            entry.account = record.accountID.flatMap { accounts[$0] }
            entry.toAccount = record.toAccountID.flatMap { accounts[$0] }
            entry.category = record.categoryID.flatMap { categories[$0] }
            entry.person = record.personID.flatMap { people[$0] }
        }

        for record in file.merchantRules {
            let rule = MerchantRule(merchant: record.merchant)
            context.insert(rule)
            rule.category = record.categoryID.flatMap { categories[$0] }
        }

        for record in file.processedMessages {
            let processed = ProcessedMessage(fingerprint: record.fingerprint, rawText: record.rawText, entryID: record.entryID)
            context.insert(processed)
            processed.receivedAt = record.receivedAt
        }

        try context.save()
    }
}
