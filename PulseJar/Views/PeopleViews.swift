import SwiftData
import SwiftUI

struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var entries: [LedgerEntry]
    @State private var adding = false
    @State private var newName = ""

    private var balances: [PersistentIdentifier: Decimal] {
        Dictionary(uniqueKeysWithValues: people.map { ($0.persistentModelID, Ledger.debtBalance(of: $0, in: entries)) })
    }

    var body: some View {
        let balances = balances
        let owedToYou = balances.values.filter { $0 > 0 }.reduce(Decimal(0), +)
        let youOwe = balances.values.filter { $0 < 0 }.reduce(Decimal(0), +)

        List {
            if !people.isEmpty {
                Section {
                    LabeledContent("Owed to you") {
                        Text(owedToYou.money()).foregroundStyle(.green).monospacedDigit()
                    }
                    LabeledContent("You owe") {
                        Text((-youOwe).money()).foregroundStyle(.red).monospacedDigit()
                    }
                }
            }
            Section {
                ForEach(people) { person in
                    let balance = balances[person.persistentModelID] ?? 0
                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        HStack {
                            Text(person.name)
                            Spacer()
                            Text(balance == 0 ? "Settled" : abs(balance).money())
                                .foregroundStyle(Ledger.debtColor(balance))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .overlay {
            if people.isEmpty {
                ContentUnavailableView(
                    "No people yet",
                    systemImage: "person.2",
                    description: Text("People are added when you review a CliQ transfer as a debt, or with +.")
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
        }
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
}

struct PersonDetailView: View {
    @Bindable var person: Person

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var confirmingDelete = false

    private var personEntries: [LedgerEntry] { entries.filter { $0.person == person } }

    var body: some View {
        let balance = Ledger.debtBalance(of: person, in: personEntries)

        List {
            Section {
                Text(Ledger.debtDescription(balance, name: person.name))
                    .font(.title3.bold())
                    .foregroundStyle(Ledger.debtColor(balance))
            }
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
            Section("History") {
                if personEntries.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach(personEntries) { entry in
                    EntryLink(entry: entry)
                }
            }
            Section {
                Button("Delete person", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
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
