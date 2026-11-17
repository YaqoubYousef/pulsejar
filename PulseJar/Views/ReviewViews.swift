import SwiftData
import SwiftUI

/// Sorts entries waiting for review one at a time, with one-tap answers.
struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date) private var entries: [LedgerEntry]
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]
    @Query(sort: \Person.name) private var people: [Person]
    @State private var skipped: Set<UUID> = []
    @State private var rememberMerchant = true

    /// Oldest first, so the queue is worked through in the order money moved.
    private var pending: [LedgerEntry] { entries.filter { $0.status == .needsReview } }

    private var current: LedgerEntry? {
        pending.first { !skipped.contains($0.id) } ?? pending.first
    }

    private var cashAccount: Account? {
        accounts.first { $0.kind == .cash && !$0.isArchived }
    }

    var body: some View {
        Group {
            if let entry = current {
                ScrollView {
                    card(for: entry)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .id(entry.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            } else {
                BrandEmptyState(title: "All caught up", message: "New CliQ transfers and unknown purchases will show up here.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .animation(.snappy, value: current?.id)
        .navigationTitle("Review")
        .toolbar {
            if pending.count > 1, let entry = current {
                Button("Skip") {
                    skipped.insert(entry.id)
                    if pending.allSatisfy({ skipped.contains($0.id) }) {
                        skipped = []
                    }
                }
            }
        }
    }

    // MARK: - Card

    private func card(for entry: LedgerEntry) -> some View {
        let position = (pending.firstIndex { $0.id == entry.id } ?? 0) + 1

        return VStack(spacing: 16) {
            if pending.count > 1 {
                Text("\(position) of \(pending.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            if let raw = entry.rawMessage, !raw.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(raw)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                    Text([entry.account?.name, entry.date.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            VStack(spacing: 4) {
                MoneyText(amount: entry.signedAmount, signed: true, showsCurrency: true, size: 40, weight: .bold)
                    .foregroundStyle(entry.signedAmount > 0 ? Theme.positive : Color.primary)
                Text(prompt(for: entry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            answers(for: entry)

            NavigationLink {
                EntryEditView(mode: .review(entry))
            } label: {
                Text("More options…")
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 6)
            }
        }
    }

    private func prompt(for entry: LedgerEntry) -> String {
        switch ReviewResolver.question(for: entry) {
        case .purchase(let merchant): return "What did you buy at \(merchant.capitalized)?"
        case .cliqIn, .cliqOut: return "What was it?"
        case .other: return entry.note.isEmpty ? "Check what this was" : entry.note
        }
    }

    // MARK: - Answers

    @ViewBuilder
    private func answers(for entry: LedgerEntry) -> some View {
        switch ReviewResolver.question(for: entry) {
        case .cliqIn(let name):
            cliqAnswers(entry, counterparty: name, incoming: true)
        case .cliqOut(let name):
            cliqAnswers(entry, counterparty: name, incoming: false)
        case .purchase(let merchant):
            purchaseAnswers(entry, merchant: merchant)
        case .other:
            NavigationLink {
                EntryEditView(mode: .review(entry))
            } label: {
                ChoiceLabel(icon: "square.and.pencil", tint: Theme.accent, title: "Open the editor", subtitle: "Choose the type, accounts and amount", suggested: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func cliqAnswers(_ entry: LedgerEntry, counterparty: String, incoming: Bool) -> some View {
        let person = ReviewResolver.matchingPerson(for: counterparty, in: people)
        let name = person?.name ?? counterparty.capitalized
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let balance = person.map { Ledger.debtBalance(of: $0, in: entries) } ?? 0
        // Incoming money most likely settles a debt they have with you, and outgoing money one you have with them.
        let settles = incoming ? balance > 0 : balance < 0

        VStack(spacing: 10) {
            Button {
                resolve(entry, incoming ? .debtIn(person: person, name: name) : .debtOut(person: person, name: name))
            } label: {
                ChoiceLabel(
                    icon: "person.fill",
                    tint: Theme.accent,
                    title: debtTitle(first: first, incoming: incoming, settles: settles),
                    subtitle: settles ? "\(incoming ? "They owe you" : "You owe them") \(abs(balance).money())" : "Recorded under People",
                    suggested: settles
                )
            }
            .buttonStyle(.plain)

            if let cash = cashAccount, cash != entry.account {
                Button {
                    resolve(entry, incoming ? .cashSwapIn(cash: cash) : .cashSwapOut(cash: cash))
                } label: {
                    ChoiceLabel(
                        icon: "banknote",
                        tint: Theme.neutral,
                        title: incoming ? "I gave \(first) cash" : "\(first) gave me cash",
                        subtitle: incoming ? "Moves money from \(cash.name) into \(entry.account?.name ?? "the bank")" : "Moves money from \(entry.account?.name ?? "the bank") into \(cash.name)"
                    )
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(categories.filter { $0.kind == (incoming ? .income : .expense) }) { category in
                    Button {
                        resolve(entry, incoming ? .income(category) : .expense(category, rememberMerchant: false))
                    } label: {
                        Label(category.name, systemImage: category.icon)
                    }
                }
            } label: {
                ChoiceLabel(
                    icon: incoming ? "briefcase.fill" : "cart.fill",
                    tint: incoming ? Theme.positive : Theme.accent,
                    title: incoming ? "Income" : "Expense",
                    subtitle: "Choose a category",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func debtTitle(first: String, incoming: Bool, settles: Bool) -> String {
        switch (incoming, settles) {
        case (true, true): return "\(first) paid me back"
        case (true, false): return "\(first) lent me money"
        case (false, true): return "I paid \(first) back"
        case (false, false): return "I lent \(first) money"
        }
    }

    private func purchaseAnswers(_ entry: LedgerEntry, merchant: String) -> some View {
        VStack(spacing: 12) {
            CategoryGrid(categories: categories.filter { $0.kind == .expense }, selection: nil) { category in
                resolve(entry, .expense(category, rememberMerchant: rememberMerchant))
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Toggle("Always use it for \(merchant.capitalized)", isOn: $rememberMerchant)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func resolve(_ entry: LedgerEntry, _ answer: ReviewResolver.Answer) {
        withAnimation(.snappy) {
            ReviewResolver.apply(answer, to: entry, context: context)
        }
        skipped.remove(entry.id)
        Haptics.success()
    }
}

/// One answer in the Review card.
struct ChoiceLabel: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var suggested = false
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if suggested {
                        Text("Suggested")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: showsChevron ? "chevron.up.chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if suggested {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Categories as a grid of one-tap icons.
struct CategoryGrid: View {
    let categories: [EntryCategory]
    let selection: EntryCategory?
    var limit: Int?
    var onMore: (() -> Void)?
    let onSelect: (EntryCategory) -> Void

    init(
        categories: [EntryCategory],
        selection: EntryCategory?,
        limit: Int? = nil,
        onMore: (() -> Void)? = nil,
        onSelect: @escaping (EntryCategory) -> Void
    ) {
        self.categories = categories
        self.selection = selection
        self.limit = limit
        self.onMore = onMore
        self.onSelect = onSelect
    }

    private var shown: [EntryCategory] {
        guard let limit, categories.count > limit else {
            return categories
        }
        var items = Array(categories.prefix(limit - 1))
        if let selection, !items.contains(selection) {
            items[items.count - 1] = selection
        }
        return items
    }

    private var hasMore: Bool {
        limit.map { categories.count > $0 } ?? false
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
            ForEach(shown) { category in
                Button {
                    Haptics.tap()
                    onSelect(category)
                } label: {
                    tile(icon: category.icon, title: shortName(category.name), selected: category == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.name)
                .accessibilityAddTraits(category == selection ? .isSelected : [])
            }
            if hasMore, let onMore {
                Button(action: onMore) {
                    tile(icon: "ellipsis", title: "More", selected: false, neutral: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tile(icon: String, title: String, selected: Bool, neutral: Bool = false) -> some View {
        VStack(spacing: 5) {
            IconBadge(systemName: icon, tint: neutral ? Theme.neutral : Theme.accent, size: 40, filled: selected)
            Text(title)
                .font(.caption2)
                .foregroundStyle(selected ? Theme.accent : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(selected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    /// "Food & Dining" → "Food", so names fit under the icon.
    private func shortName(_ name: String) -> String {
        name.components(separatedBy: " & ").first ?? name
    }
}
