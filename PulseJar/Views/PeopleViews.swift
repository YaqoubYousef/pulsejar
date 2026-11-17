import SwiftData
import SwiftUI

struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var entries: [LedgerEntry]
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @State private var adding = false
    @State private var newName = ""
    @State private var settling: SettleRequest?

    private var balances: [PersistentIdentifier: Decimal] {
        Dictionary(uniqueKeysWithValues: people.map { ($0.persistentModelID, Ledger.debtBalance(of: $0, in: entries)) })
    }

    var body: some View {
        let balances = balances
        let owedToYou = balances.values.filter { $0 > 0 }.reduce(Decimal(0), +)
        let youOwe = balances.values.filter { $0 < 0 }.reduce(Decimal(0), +)
        let open = people
            .filter { (balances[$0.persistentModelID] ?? 0) != 0 }
            .sorted { abs(balances[$0.persistentModelID] ?? 0) > abs(balances[$1.persistentModelID] ?? 0) }
        let settled = people.filter { (balances[$0.persistentModelID] ?? 0) == 0 }

        List {
            if !people.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        totalTile("They owe you", amount: owedToYou, color: Theme.positive)
                        totalTile("You owe", amount: -youOwe, color: Theme.accent)
                    }
                    .listRowInsets(EdgeInsets())
                }
                .listRowBackground(Color.clear)
            }

            if !open.isEmpty {
                Section("Open") {
                    ForEach(open) { person in
                        let balance = balances[person.persistentModelID] ?? 0
                        NavigationLink {
                            PersonDetailView(person: person)
                        } label: {
                            PersonRow(person: person, balance: balance, openedAt: Ledger.debtOpenedAt(for: person, in: entries))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                settling = SettleRequest(person: person, balance: balance)
                            } label: {
                                Label("Settle up", systemImage: "checkmark.circle")
                            }
                            .tint(Theme.positive)
                        }
                    }
                }
                .cardRows()
            }

            if !settled.isEmpty {
                Section("Settled") {
                    ForEach(settled) { person in
                        NavigationLink {
                            PersonDetailView(person: person)
                        } label: {
                            PersonRow(person: person, balance: 0, openedAt: nil)
                        }
                    }
                }
                .cardRows()
            }
        }
        .themedBackground()
        .overlay {
            if people.isEmpty {
                BrandEmptyState(
                    title: "No people yet",
                    message: "People are added when you review a CliQ transfer as money lent or borrowed, or with +."
                )
            }
        }
        .navigationTitle("People")
        .toolbar {
            Button {
                newName = ""
                adding = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add person")
        }
        .settleUpDialog($settling, accounts: accounts, context: context)
        .alert("New person", isPresented: $adding) {
            TextField("Name", text: $newName)
            Button("Add") {
                guard !newName.trimmed.isEmpty else {
                    return
                }
                context.insert(Person(name: newName.trimmed))
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func totalTile(_ title: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            MoneyText(amount: amount, size: 20, weight: .bold)
                .foregroundStyle(amount == 0 ? Color.secondary : color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct PersonRow: View {
    let person: Person
    let balance: Decimal
    let openedAt: Date?

    private var initials: String {
        let words = person.name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    private var caption: String {
        let direction = balance > 0 ? "Owes you" : balance < 0 ? "You owe" : "Settled"
        guard balance != 0, let openedAt else {
            return direction
        }
        return "\(direction) · since \(openedAt.formatted(.dateTime.day().month(.abbreviated)))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(balance == 0 ? Color.secondary : Brand.night)
                .frame(width: 36, height: 36)
                .background(balance == 0 ? Theme.neutralSoft : (balance > 0 ? Brand.sand : Brand.blend), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .lineLimit(1)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if balance != 0 {
                MoneyText(amount: abs(balance))
                    .foregroundStyle(Ledger.debtColor(balance))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Who to settle with, and how much is open.
struct SettleRequest: Identifiable {
    let person: Person
    let balance: Decimal
    var id: PersistentIdentifier { person.persistentModelID }
}

extension View {
    /// Asks which account the repayment went through, then records it.
    func settleUpDialog(_ request: Binding<SettleRequest?>, accounts: [Account], context: ModelContext) -> some View {
        confirmationDialog(
            request.wrappedValue.map { $0.balance > 0 ? "Where did \($0.person.name) pay you?" : "How did you pay \($0.person.name)?" } ?? "",
            isPresented: Binding(get: { request.wrappedValue != nil }, set: { if !$0 { request.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: request.wrappedValue
        ) { item in
            ForEach(accounts.filter { !$0.isArchived }) { account in
                Button(account.name) {
                    Ledger.settleUp(item.person, balance: item.balance, account: account, context: context)
                    Haptics.success()
                    request.wrappedValue = nil
                }
            }
        } message: { item in
            Text("Records \(abs(item.balance).money()) \(item.balance > 0 ? "received" : "paid"), so the balance is settled.")
        }
    }
}

struct PersonDetailView: View {
    @Bindable var person: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @State private var confirmingDelete = false
    @State private var settling: SettleRequest?

    private var personEntries: [LedgerEntry] { entries.filter { $0.person == person } }

    var body: some View {
        let balance = Ledger.debtBalance(of: person, in: personEntries)

        List {
            Section {
                Text(Ledger.debtDescription(balance, name: person.name))
                    .font(.title3.bold())
                    .foregroundStyle(Ledger.debtColor(balance))
                if balance != 0 {
                    Button {
                        settling = SettleRequest(person: person, balance: balance)
                    } label: {
                        Label("Settle up", systemImage: "checkmark.circle")
                    }
                }
            }
            .cardRows()
            Section {
                TextField("Name", text: $person.name)
                TextField("Name in bank messages", text: Binding(
                    get: { person.bankName ?? "" },
                    set: { person.bankName = $0.trimmed.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.characters)
            } footer: {
                Text("When a CliQ message has this name, this person is suggested.")
            }
            .cardRows()
            Section("History") {
                if personEntries.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(personEntries) { entry in
                    EntryLink(entry: entry)
                }
            }
            .cardRows()
            Section {
                Button("Delete person", role: .destructive) {
                    confirmingDelete = true
                }
            }
            .cardRows()
        }
        .themedBackground()
        .settleUpDialog($settling, accounts: accounts, context: context)
        .navigationTitle(person.name)
        .confirmationDialog("Delete \(person.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(person)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Their transactions stay, without a person.")
        }
    }
}
