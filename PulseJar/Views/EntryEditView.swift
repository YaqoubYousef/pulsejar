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
    @State private var showsDetails = false
    @State private var showsAllCategories = false
    @FocusState private var amountFocused: Bool

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
                .cardRows()
            }

            Section {
                amountHeader
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            .listRowBackground(Color.clear)

            if !isAdjustment {
                Section {
                    purposeChips
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text(purposeHint)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                if showsDetails || purpose == .transfer || isAdjustment || primaryAccount == nil {
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
                } else {
                    Button {
                        withAnimation { showsDetails = true }
                    } label: {
                        HStack {
                            Label(detailsSummary, systemImage: primaryAccount?.kind.icon ?? "building.columns")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Change")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .cardRows()

            if !isAdjustment {
                switch purpose {
                case .regular:
                    Section {
                        CategoryGrid(
                            categories: visibleCategories,
                            selection: category,
                            limit: showsAllCategories ? nil : 8,
                            onMore: { withAnimation { showsAllCategories = true } }
                        ) { selected in
                            category = category == selected ? nil : selected
                        }
                        .padding(.vertical, 6)
                        if let merchant, flow == .moneyOut {
                            Toggle("Always use this category for \(merchant.capitalized)", isOn: $rememberMerchant)
                        }
                    } header: {
                        Text("Category")
                    }
                    .cardRows()
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
                                .textInputAutocapitalization(.words)
                        }
                    } footer: {
                        Text("The People tab shows who owes whom.")
                    }
                    .cardRows()
                case .transfer:
                    EmptyView()
                }
            }

            Section {
                TextField("Note", text: $note, axis: .vertical)
            }
            .cardRows()

            if !isAdding {
                Section {
                    Button("Delete transaction", role: .destructive) {
                        confirmingDelete = true
                    }
                }
                .cardRows()
            }
        }
        .themedBackground()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text(saveTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isAdding {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            guard isAdding else {
                return
            }
            // Wait for the sheet to finish presenting, then open the keypad.
            try? await Task.sleep(for: .milliseconds(450))
            amountFocused = true
        }
        .onChange(of: errorMessage) { _, message in
            if message != nil {
                Haptics.warning()
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

    // MARK: - Pieces

    private var parsedAmount: Decimal? {
        Money.parse(amountText).flatMap { $0 > 0 ? $0 : nil }
    }

    private var saveTitle: String {
        if mode.isReview {
            return "Confirm"
        }
        guard let parsedAmount else {
            return "Save"
        }
        return "Save \(parsedAmount.money())"
    }

    private var detailsSummary: String {
        let account = primaryAccount?.name ?? "Choose account"
        let day: String
        if Calendar.current.isDateInToday(date) {
            day = "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.day().month(.abbreviated))
        }
        return "\(account) · \(day), \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var amountHeader: some View {
        VStack(spacing: 10) {
            Picker("Direction", selection: $flow) {
                Text("Out").tag(Flow.moneyOut)
                Text("In").tag(Flow.moneyIn)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .disabled(isBankEntry)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isBankEntry {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Set by the bank message")
                }
                TextField("0.000", text: $amountText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .fixedSize()
                    .disabled(isBankEntry)
                    .foregroundStyle(flow == .moneyIn ? Theme.positive : Color.primary)
                    .accessibilityLabel("Amount")
                Text("JOD")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var purposeChips: some View {
        HStack(spacing: 8) {
            chip(flow == .moneyOut ? "Expense" : "Income", value: .regular)
            chip(flow == .moneyOut ? "Lent / repaid" : "Borrowed / repaid", value: .debt)
            chip("Transfer", value: .transfer)
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ title: String, value: Purpose) -> some View {
        let selected = purpose == value
        return Button {
            withAnimation(.snappy) { purpose = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Theme.background : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Color.primary : Theme.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        Haptics.success()
        try? context.save()
        MessageIngestor.refreshBadge(context)
        dismiss()
    }
}
