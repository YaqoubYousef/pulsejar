import SwiftData
import SwiftUI

struct CategoryTotal: Identifiable {
    let name: String
    let icon: String
    let total: Decimal
    var id: String { name }
}

struct HomeView: View {
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]
    @State private var addingEntry = false
    @State private var addingAccount = false

    private var visibleAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var pendingCount: Int { entries.filter { $0.status == .needsReview }.count }

    private var total: Decimal {
        visibleAccounts.reduce(Decimal(0)) { $0 + Ledger.balance(of: $1, in: entries) }
    }

    private var monthEntries: [LedgerEntry] {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else {
            return []
        }
        return entries.filter { month.contains($0.date) && $0.status != .reversed }
    }

    private var monthIncome: Decimal {
        monthEntries.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var monthExpenses: Decimal {
        monthEntries.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var topCategories: [CategoryTotal] {
        let expenses = monthEntries.filter { $0.kind == .expense }
        let groups = Dictionary(grouping: expenses) { $0.category?.name ?? "Not categorized" }
        let totals = groups.map { name, items in
            CategoryTotal(
                name: name,
                icon: items.first?.category?.icon ?? "questionmark.circle",
                total: items.reduce(Decimal(0)) { $0 + $1.amount }
            )
        }
        return Array(totals.sorted { $0.total > $1.total }.prefix(6))
    }

    var body: some View {
        List {
            if pendingCount > 0 {
                Section {
                    NavigationLink {
                        ReviewView()
                    } label: {
                        Label("\(pendingCount) waiting for review", systemImage: "exclamationmark.bubble.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(total.money())
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }

            Section("Accounts") {
                ForEach(visibleAccounts) { account in
                    NavigationLink(value: account) {
                        HStack {
                            Label(account.name, systemImage: account.kind.icon)
                            if Ledger.mismatch(for: account, in: entries) != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            }
                            Spacer()
                            Text(Ledger.balance(of: account, in: entries).money())
                                .monospacedDigit()
                        }
                    }
                }
                Button {
                    addingAccount = true
                } label: {
                    Label("Add account", systemImage: "plus")
                }
            }

            Section("This month") {
                LabeledContent("Income") {
                    Text(monthIncome.money()).foregroundStyle(.green).monospacedDigit()
                }
                LabeledContent("Expenses") {
                    Text(monthExpenses.money()).monospacedDigit()
                }
                ForEach(topCategories) { item in
                    LabeledContent {
                        Text(item.total.money()).monospacedDigit()
                    } label: {
                        Label(item.name, systemImage: item.icon)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Finance")
        .navigationDestination(for: Account.self) { account in
            AccountDetailView(account: account)
        }
        .toolbar {
            Button {
                addingEntry = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $addingEntry) {
            NavigationStack { EntryEditView(mode: .add) }
        }
        .sheet(isPresented: $addingAccount) {
            NavigationStack { AccountEditView(account: nil) }
        }
    }
}
