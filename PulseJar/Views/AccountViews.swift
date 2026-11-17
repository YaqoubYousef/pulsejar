import Charts
import SwiftData
import SwiftUI

private struct BalancePoint: Identifiable {
    let day: Date
    let balance: Double
    var id: Date { day }
}

struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var editing = false
    @State private var addingEntry = false

    private var accountEntries: [LedgerEntry] {
        entries.filter { $0.account == account || $0.toAccount == account }
    }

    /// End-of-day balance for the last 30 days.
    private var history: [BalancePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let relevant = accountEntries
        return (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: day)
            else {
                return nil
            }
            let balance = Ledger.balance(of: account, in: relevant, asOf: endOfDay)
            return BalancePoint(day: day, balance: NSDecimalNumber(decimal: balance).doubleValue)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.kind.title + (account.bankMask.map { " · \($0)" } ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MoneyText(amount: Ledger.balance(of: account, in: entries), showsCurrency: true, currency: account.currency, size: 34, weight: .bold)
                    if accountEntries.count > 1 {
                        balanceChart
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            }
            .cardRows()

            if let mismatch = Ledger.mismatch(for: account, in: entries) {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Doesn't match the bank", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.headline)
                        Text("On \(mismatch.date.formatted(date: .abbreviated, time: .shortened)) the bank said \(mismatch.bankBalance.money()), but the app shows \(mismatch.appBalance.money()). A message may be missing — paste it in Settings → Paste bank messages, or match the bank balance.")
                            .font(.footnote)
                    }
                    Button("Match bank balance") {
                        let adjustment = LedgerEntry(kind: .adjustment, amount: mismatch.bankBalance - mismatch.appBalance, date: mismatch.date)
                        context.insert(adjustment)
                        adjustment.account = account
                        adjustment.note = "Matched to the bank balance"
                        try? context.save()
                        Haptics.success()
                    }
                }
                .cardRows()
            }

            Section("Transactions") {
                if accountEntries.isEmpty {
                    Text("No transactions yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(accountEntries) { entry in
                    EntryLink(entry: entry, perspective: account)
                }
            }
            .cardRows()
        }
        .themedBackground()
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    addingEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { AccountEditView(account: account) }
        }
        .sheet(isPresented: $addingEntry) {
            NavigationStack { EntryEditView(mode: .add, defaultAccount: account) }
        }
    }

    private var balanceChart: some View {
        let points = history
        let values = points.map(\.balance)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max((high - low) * 0.15, 1)

        return VStack(alignment: .leading, spacing: 4) {
            Chart(points) { point in
                AreaMark(
                    x: .value("Day", point.day),
                    yStart: .value("Floor", low - padding),
                    yEnd: .value("Balance", point.balance)
                )
                .foregroundStyle(Theme.accent.opacity(0.15))
                .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.day), y: .value("Balance", point.balance))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: (low - padding)...(high + padding))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 70)
            Text("Last 30 days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Balance over the last 30 days, from \(Decimal(values.first ?? 0).spokenMoney()) to \(Decimal(values.last ?? 0).spokenMoney())")
    }
}

struct AccountEditView: View {
    let account: Account?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]

    @State private var name: String
    @State private var kind: AccountKind
    @State private var bankMask: String
    @State private var openingText: String
    @State private var isArchived: Bool
    @State private var confirmingDelete = false

    init(account: Account?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _kind = State(initialValue: account?.kind ?? .bank)
        _bankMask = State(initialValue: account?.bankMask ?? "")
        _openingText = State(initialValue: Money.editableText(account?.openingBalance ?? 0))
        _isArchived = State(initialValue: account?.isArchived ?? false)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach(AccountKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.icon).tag(kind)
                    }
                }
            }
            .cardRows()
            Section {
                TextField("Account number in messages, e.g. 1600*1380", text: $bankMask)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Bank messages with this number are recorded in this account. Leave empty for cash.")
            }
            .cardRows()
            Section {
                TextField("Opening balance", text: $openingText)
                    .keyboardType(.decimalPad)
            } footer: {
                Text("The balance before the first transaction in the app. For accounts created from a bank message this is set automatically.")
            }
            .cardRows()
            if account != nil {
                Section {
                    Toggle("Hide account", isOn: $isArchived)
                    Button("Delete account", role: .destructive) {
                        confirmingDelete = true
                    }
                }
                .cardRows()
            }
        }
        .themedBackground()
        .navigationTitle(account == nil ? "New account" : "Edit account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmed.isEmpty)
            }
        }
        .confirmationDialog("Delete this account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account and its transactions", role: .destructive) {
                if let account {
                    context.delete(account)
                    try? context.save()
                    MessageIngestor.refreshBadge(context)
                }
                dismiss()
            }
        } message: {
            Text("Its transactions are deleted too. This can't be undone. Use \"Hide account\" to keep the history.")
        }
    }

    private func save() {
        let target: Account
        if let account {
            target = account
        } else {
            target = Account(name: name.trimmed, kind: kind, sortOrder: (accounts.map(\.sortOrder).max() ?? 0) + 1)
            context.insert(target)
        }
        target.name = name.trimmed
        target.kind = kind
        let mask = bankMask.filter { !$0.isWhitespace }
        target.bankMask = mask.isEmpty ? nil : mask
        target.openingBalance = Money.parse(openingText) ?? 0
        target.isArchived = isArchived
        try? context.save()
        dismiss()
    }
}
