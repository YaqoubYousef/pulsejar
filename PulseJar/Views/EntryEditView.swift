import SwiftData
import SwiftUI

/// Add, edit, or review a transaction.
///
/// Review decides what a bank movement really was: an expense or income, a debt with a person,
/// or a transfer with another of your accounts (e.g. got CliQ, paid back in cash).
struct EntryEditView: View {
    enum Mode {
        case add
        case edit(LedgerEntry)
        case review(LedgerEntry)

        var entry: LedgerEntry? {
            switch self {
            case .add: return nil
            case .edit(let entry), .review(let entry): return entry
            }
        }

        var isReview: Bool {
            if case .review = self {
                return true
            }
            return false
        }
    }

    enum Flow: Hashable {
        case moneyOut, moneyIn
    }

    enum Purpose: Hashable {
        case regular, debt, transfer
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]
    @Query(sort: \Person.name) private var people: [Person]

    let mode: Mode

    @State private var flow: Flow
    @State private var purpose: Purpose
    @State private var amountText: String
    @State private var date: Date
    @State private var primaryAccount: Account?
    @State private var otherAccount: Account?
    @State private var category: EntryCategory?
    @State private var person: Person?
    @State private var newPersonName = ""
    @State private var note: String
    @State private var rememberMerchant = true
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var didPrefill = false

    init(mode: Mode, defaultAccount: Account? = nil) {
        self.mode = mode
        let entry = mode.entry

        var flow = Flow.moneyOut
        var purpose = Purpose.regular
        var primary = defaultAccount
        var other: Account?

        if let entry {
            primary = entry.account
            switch entry.kind {
            case .expense:
                flow = .moneyOut
            case .income:
                flow = .moneyIn
            case .adjustment:
                flow = entry.amount < 0 ? .moneyOut : .moneyIn
            case .debtGiven:
                flow = .moneyOut
                purpose = .debt
            case .debtReceived:
                flow = .moneyIn
                purpose = .debt
            case .transfer:
                purpose = .transfer
                if entry.account == nil {
                    flow = .moneyIn
                    primary = entry.toAccount
                } else {
                    flow = .moneyOut
                    other = entry.toAccount
                }
            }
        }

        _flow = State(initialValue: flow)
        _purpose = State(initialValue: purpose)
        _amountText = State(initialValue: entry.map { Money.editableText(abs($0.amount)) } ?? "")
        _date = State(initialValue: entry?.date ?? .now)
        _primaryAccount = State(initialValue: primary)
        _otherAccount = State(initialValue: other)
        _category = State(initialValue: entry?.category)
        _person = State(initialValue: entry?.person)
        _note = State(initialValue: entry?.note ?? "")
    }

    // MARK: - Derived state

    private var isBankEntry: Bool { mode.entry?.source == .bankMessage }
    private var isAdjustment: Bool { mode.entry?.kind == .adjustment }
    private var isAdding: Bool { mode.entry == nil }
    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived || $0 == primaryAccount || $0 == otherAccount } }
    private var cashAccount: Account? { accounts.first { $0.kind == .cash && !$0.isArchived && $0 != primaryAccount } }
    private var merchant: String? { mode.entry?.merchant }

    private var visibleCategories: [EntryCategory] {
        let kind: CategoryKind = flow == .moneyOut ? .expense : .income
        return categories.filter { $0.kind == kind }
    }

    private var title: String {
        if mode.isReview {
            return "Review"
        }
        return isAdding ? "New transaction" : "Transaction"
    }

    private var primaryLabel: String {
        guard purpose == .transfer else {
            return "Account"
        }
        return flow == .moneyOut ? "From" : "Into"
    }

    private var otherLabel: String {
        flow == .moneyOut ? "To" : "From"
    }

    private var purposeHint: String {
        switch (purpose, flow) {
        case (.regular, .moneyOut): return "Money you spent."
        case (.regular, .moneyIn): return "Money you earned or received for good."
        case (.debt, .moneyOut): return "You lent money to someone, or paid back money you owed them."
        case (.debt, .moneyIn): return "You borrowed money from someone, or they paid you back."
        case (.transfer, .moneyOut): return "Moved to another of your accounts. Example: you sent CliQ and got cash back."
        case (.transfer, .moneyIn): return "Came from another of your accounts. Example: someone sent you CliQ and you gave them cash."
        }
    }

    // MARK: - Body

    var body: some View {
        Form {
            if let raw = mode.entry?.rawMessage, !raw.isEmpty {
                Section("Bank message") {
                    Text(raw)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                Picker("Direction", selection: $flow) {
                    Text("Money out").tag(Flow.moneyOut)
                    Text("Money in").tag(Flow.moneyIn)
                }
                .pickerStyle(.segmented)
                .disabled(isBankEntry)

                if !isAdjustment {
                    Picker("Type", selection: $purpose) {
                        Text(flow == .moneyOut ? "Expense" : "Income").tag(Purpose.regular)
                        Text("Debt").tag(Purpose.debt)
                        Text("Transfer").tag(Purpose.transfer)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                if !isAdjustment {
                    Text(purposeHint)
                }
            }

            Section {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .disabled(isBankEntry)
                DatePicker("Date", selection: $date)

                Picker(primaryLabel, selection: $primaryAccount) {
                    Text("Choose…").tag(Account?.none)
                    ForEach(activeAccounts) { account in
                        Text(account.name).tag(Optional(account))
                    }
                }
                .disabled(isBankEntry)

                if purpose == .transfer && !isAdjustment {
                    Picker(otherLabel, selection: $otherAccount) {
                        Text("Choose…").tag(Account?.none)
                        ForEach(activeAccounts.filter { $0 != primaryAccount }) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                }
            }

            if !isAdjustment {
                switch purpose {
                case .regular:
                    Section {
                        Picker("Category", selection: $category) {
                            Text("None").tag(EntryCategory?.none)
                            ForEach(visibleCategories) { category in
                                Label(category.name, systemImage: category.icon).tag(Optional(category))
                            }
                        }
                        if let merchant, flow == .moneyOut {
                            Toggle("Always use this category for \(merchant.capitalized)", isOn: $rememberMerchant)
                        }
                    }
                case .debt:
                    Section {
                        Picker("Person", selection: $person) {
                            Text("New person…").tag(Person?.none)
                            ForEach(people) { person in
                                Text(person.name).tag(Optional(person))
                            }
                        }
                        if person == nil {
                            TextField("Name", text: $newPersonName)
                        }
                    } footer: {
                        Text("The People tab shows who owes whom.")
                    }
                case .transfer:
                    EmptyView()
                }
            }

            Section {
                TextField("Note", text: $note, axis: .vertical)
            }

            if !isAdding {
                Section {
                    Button("Delete transaction", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(mode.isReview ? "Confirm" : "Save", action: save)
            }
            if isAdding {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .alert("Can't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let entry = mode.entry {
                    Ledger.delete(entry, context: context)
                }
                dismiss()
            }
        } message: {
            if mode.entry?.linkedEntryID != nil {
                Text("Its linked reversal is deleted too.")
            }
        }
        .onAppear(perform: prefill)
        .onChange(of: purpose) { _, newValue in
            if newValue == .transfer, otherAccount == nil {
                otherAccount = cashAccount
            }
        }
        .onChange(of: flow) { _, _ in
            if let category, !visibleCategories.contains(category) {
                self.category = nil
            }
        }
    }

    // MARK: - Actions

    private func prefill() {
        guard !didPrefill else {
            return
        }
        didPrefill = true

        if primaryAccount == nil {
            primaryAccount = accounts.first { !$0.isArchived && $0.kind == .bank } ?? accounts.first { !$0.isArchived }
        }
        if let counterparty = mode.entry?.counterparty {
            if person == nil {
                person = people.first { $0.bankName?.uppercased() == counterparty.uppercased() }
            }
            if newPersonName.isEmpty {
                newPersonName = counterparty.capitalized
            }
        }
    }

    private func save() {
        guard let amount = Money.parse(amountText), amount > 0 else {
            errorMessage = "Enter an amount greater than zero."
            return
        }
        guard let primary = primaryAccount else {
            errorMessage = "Choose an account."
            return
        }
        if purpose == .transfer, !isAdjustment, otherAccount == nil || otherAccount == primary {
            errorMessage = "Choose the other account of the transfer."
            return
        }
        if purpose == .debt, !isAdjustment, person == nil, newPersonName.trimmed.isEmpty {
            errorMessage = "Choose the person or type a name."
            return
        }

        let entry: LedgerEntry
        if let existing = mode.entry {
            entry = existing
        } else {
            entry = LedgerEntry(kind: .expense, amount: amount, date: date)
            context.insert(entry)
        }

        var reportedBalances: [PersistentIdentifier: Decimal] = [:]
        if let account = entry.account, let balance = entry.bankBalance {
            reportedBalances[account.persistentModelID] = balance
        }
        if let account = entry.toAccount, let balance = entry.toBankBalance {
            reportedBalances[account.persistentModelID] = balance
        }

        entry.date = date
        entry.note = note.trimmed

        if isAdjustment {
            entry.amount = flow == .moneyOut ? -amount : amount
            entry.account = primary
            finish()
            return
        }

        entry.amount = amount
        entry.account = primary
        entry.toAccount = nil
        entry.category = nil
        entry.person = nil

        switch (purpose, flow) {
        case (.regular, .moneyOut):
            entry.kind = .expense
            entry.category = category
        case (.regular, .moneyIn):
            entry.kind = .income
            entry.category = category
        case (.debt, .moneyOut):
            entry.kind = .debtGiven
            entry.person = resolvePerson(counterparty: entry.counterparty)
        case (.debt, .moneyIn):
            entry.kind = .debtReceived
            entry.person = resolvePerson(counterparty: entry.counterparty)
        case (.transfer, .moneyOut):
            entry.kind = .transfer
            entry.toAccount = otherAccount
        case (.transfer, .moneyIn):
            entry.kind = .transfer
            entry.account = otherAccount
            entry.toAccount = primary
        }

        entry.bankBalance = entry.account.flatMap { reportedBalances[$0.persistentModelID] }
        entry.toBankBalance = entry.toAccount.flatMap { reportedBalances[$0.persistentModelID] }
        if entry.status != .reversed {
            entry.status = .confirmed
        }

        if entry.kind == .expense, rememberMerchant, let merchant = entry.merchant, let category {
            Ledger.rememberMerchant(merchant, category: category, context: context)
        }
        finish()
    }

    private func resolvePerson(counterparty: String?) -> Person {
        if let person {
            if person.bankName == nil, let counterparty {
                person.bankName = counterparty.uppercased()
            }
            return person
        }
        let newPerson = Person(name: newPersonName.trimmed)
        context.insert(newPerson)
        newPerson.bankName = counterparty?.uppercased()
        return newPerson
    }

    private func finish() {
        try? context.save()
        MessageIngestor.refreshBadge(context)
        dismiss()
    }
}
