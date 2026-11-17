import SwiftData
import SwiftUI

private struct DayGroup: Identifiable {
    let day: Date
    let entries: [LedgerEntry]
    var id: Date { day }

    /// What the day did to your money: spending and income, ignoring transfers and reversed entries.
    var net: Decimal {
        entries
            .filter { $0.status != .reversed && $0.kind != .transfer && $0.kind != .adjustment }
            .reduce(Decimal(0)) { $0 + $1.signedAmount }
    }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return day.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

enum EntryFilter: String, CaseIterable, Identifiable {
    case all, spending, income, transfers, debts, review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .spending: return "Spending"
        case .income: return "Income"
        case .transfers: return "Transfers"
        case .debts: return "People"
        case .review: return "Review"
        }
    }

    func matches(_ entry: LedgerEntry) -> Bool {
        switch self {
        case .all: return true
        case .spending: return entry.kind == .expense && entry.status != .needsReview
        case .income: return entry.kind == .income && entry.status != .needsReview
        case .transfers: return entry.kind == .transfer
        case .debts: return entry.kind == .debtGiven || entry.kind == .debtReceived
        case .review: return entry.status == .needsReview
        }
    }
}

struct EntriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var searchText = ""
    @State private var filter: EntryFilter = .all
    @State private var addingEntry = false
    @State private var recategorizing: LedgerEntry?
    @State private var deleting: LedgerEntry?

    private var pendingCount: Int { entries.filter { $0.status == .needsReview }.count }

    private var groups: [DayGroup] {
        let query = searchText.trimmed.lowercased()
        let filtered = entries.filter { entry in
            filter.matches(entry) && (query.isEmpty || entry.searchText.contains(query) || Money.editableText(entry.amount).contains(query))
        }
        let byDay = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { DayGroup(day: $0, entries: byDay[$0] ?? []) }
    }

    var body: some View {
        let groups = groups

        List {
            Section {
                filterChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if filter == .review && pendingCount > 0 {
                Section {
                    NavigationLink {
                        ReviewView()
                    } label: {
                        Label("Sort them one by one", systemImage: "rectangle.stack")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .cardRows()
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        EntryLink(entry: entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // No destructive role: that would hide the row before the confirmation.
                                Button {
                                    deleting = entry
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                                if entry.kind == .expense || entry.kind == .income {
                                    Button {
                                        recategorizing = entry
                                    } label: {
                                        Label("Category", systemImage: "tag")
                                    }
                                    .tint(Theme.neutral)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        if group.net != 0 {
                            MoneyText(amount: group.net, signed: true, size: 13)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .textCase(nil)
                }
                .cardRows()
            }
        }
        .themedBackground()
        .overlay {
            if entries.isEmpty {
                BrandEmptyState(title: "No transactions yet", message: "Add one with +, or set up automatic bank messages in Settings.")
            } else if groups.isEmpty {
                ContentUnavailableView(
                    filter == .review ? "Nothing to review" : "No matches",
                    systemImage: filter == .review ? "checkmark.circle" : "magnifyingglass",
                    description: Text(filter == .review ? "You're all caught up." : "Try another filter or search.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Merchant, person, note or amount")
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Transactions")
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
        .sheet(item: $recategorizing) { entry in
            CategoryPickerSheet(entry: entry)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { entry in
            Button("Delete", role: .destructive) {
                Ledger.delete(entry, context: context)
                deleting = nil
            }
        } message: { entry in
            Text(entry.linkedEntryID != nil ? "Its linked reversal is deleted too. This can't be undone." : "This can't be undone.")
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EntryFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.title)
                            if item == .review && pendingCount > 0 {
                                Text("\(pendingCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Theme.accent, in: Capsule())
                            }
                        }
                        .font(.subheadline.weight(filter == item ? .semibold : .regular))
                        .foregroundStyle(filter == item ? Theme.background : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filter == item ? Color.primary : Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

/// Changes a transaction's category without opening the editor.
struct CategoryPickerSheet: View {
    let entry: LedgerEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]

    var body: some View {
        NavigationStack {
            ScrollView {
                CategoryGrid(
                    categories: categories.filter { $0.kind == (entry.kind == .income ? .income : .expense) },
                    selection: entry.category
                ) { category in
                    entry.category = category
                    if entry.status == .needsReview {
                        entry.status = .confirmed
                    }
                    if entry.kind == .expense, let merchant = entry.merchant {
                        Ledger.rememberMerchant(merchant, category: category, context: context)
                    }
                    try? context.save()
                    MessageIngestor.refreshBadge(context)
                    Haptics.success()
                    dismiss()
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle(entry.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
