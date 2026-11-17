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
    private var pending: [LedgerEntry] { entries.filter { $0.status == .needsReview } }

    private var total: Decimal {
        visibleAccounts.reduce(Decimal(0)) { $0 + Ledger.balance(of: $1, in: entries) }
    }

    private var month: DateInterval? {
        Calendar.current.dateInterval(of: .month, for: .now)
    }

    private var monthEntries: [LedgerEntry] {
        guard let month else {
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

    private var daysLeft: Int {
        guard let month else {
            return 0
        }
        let today = Calendar.current.startOfDay(for: .now)
        return max(0, Calendar.current.dateComponents([.day], from: today, to: month.end).day ?? 0) - 1
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                balanceCard

                if !pending.isEmpty {
                    reviewCallout
                }

                accountsStrip

                spendingSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("PulseJar")
        .navigationDestination(for: Account.self) { account in
            AccountDetailView(account: account)
        }
        .toolbar {
            Button {
                addingEntry = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add transaction")
        }
        .sheet(isPresented: $addingEntry) {
            NavigationStack { EntryEditView(mode: .add) }
        }
        .sheet(isPresented: $addingAccount) {
            NavigationStack { AccountEditView(account: nil) }
        }
    }

    // MARK: - Balance card

    private var balanceCard: some View {
        let monthName = Date.now.formatted(.dateTime.month(.wide))
        let ratio = monthIncome > 0 ? NSDecimalNumber(decimal: monthExpenses / monthIncome).doubleValue : nil

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total balance")
                    .font(.subheadline)
                    .foregroundStyle(Brand.cream.opacity(0.7))
                MoneyText(amount: total, showsCurrency: true, size: 36, weight: .bold)
                    .foregroundStyle(Brand.cream)
            }

            HStack(spacing: 10) {
                flowTile(title: "In · \(monthName)", amount: monthIncome, color: Color(light: 0x9BD8A9, dark: 0x9BD8A9))
                flowTile(title: "Out · \(monthName)", amount: -monthExpenses, color: Brand.cream)
            }

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.cream.opacity(0.12))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * min(1, ratio ?? (monthExpenses > 0 ? 1 : 0)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)

                Text(spendingSummary(ratio: ratio))
                    .font(.caption)
                    .foregroundStyle(Brand.cream.opacity(0.65))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func flowTile(title: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Brand.cream.opacity(0.65))
            MoneyText(amount: amount, signed: true, size: 16, weight: .semibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.cream.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func spendingSummary(ratio: Double?) -> String {
        let days = daysLeft == 1 ? "1 day left" : "\(daysLeft) days left"
        guard let ratio else {
            return monthExpenses > 0 ? "No income recorded this month · \(days)" : "Nothing spent yet this month · \(days)"
        }
        return "Spent \(Int((ratio * 100).rounded()))% of what came in · \(days)"
    }

    // MARK: - Review

    private var reviewCallout: some View {
        let oldest = pending.map(\.date).min()
        let count = pending.count
        return NavigationLink {
            ReviewView()
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "tray.full.fill", tint: Theme.accent, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? "1 transaction to sort" : "\(count) transactions to sort")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let oldest {
                        Text("Oldest arrived \(oldest.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text("Review")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accent, in: Capsule())
            }
            .padding(12)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accounts

    private var accountsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visibleAccounts) { account in
                        NavigationLink(value: account) {
                            accountCard(account)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        addingAccount = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 52)
                            .frame(maxHeight: .infinity)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel("Add account")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .scrollClipDisabled()
        }
    }

    private func accountCard(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconBadge(systemName: account.kind.icon, size: 30)
                Spacer()
                if Ledger.mismatch(for: account, in: entries) != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Doesn't match the bank")
                }
            }
            Text(account.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            MoneyText(amount: Ledger.balance(of: account, in: entries), size: 17, weight: .semibold)
        }
        .padding(12)
        .frame(width: 140, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Spending

    @ViewBuilder
    private var spendingSection: some View {
        let categories = topCategories
        let largest = categories.first?.total ?? 0

        VStack(alignment: .leading, spacing: 8) {
            Text("Where it went")
                .font(.headline)
            if categories.isEmpty {
                Text("Spending this month will show up here by category.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, item in
                        categoryRow(item, share: largest > 0 ? NSDecimalNumber(decimal: item.total / largest).doubleValue : 0)
                        if index < categories.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func categoryRow(_ item: CategoryTotal, share: Double) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: item.icon, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.name)
                        .lineLimit(1)
                    Spacer()
                    MoneyText(amount: item.total)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.accentSoft)
                        Capsule().fill(Theme.accent).frame(width: proxy.size.width * share)
                    }
                }
                .frame(height: 5)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
