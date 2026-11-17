import SwiftData
import SwiftUI

private struct DayGroup: Identifiable {
    let day: Date
    let entries: [LedgerEntry]
    var id: Date { day }
}

struct EntriesView: View {
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var searchText = ""
    @State private var addingEntry = false

    private var groups: [DayGroup] {
        let query = searchText.trimmed.lowercased()
        let filtered = query.isEmpty ? entries : entries.filter { $0.searchText.contains(query) }
        let byDay = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { DayGroup(day: $0, entries: byDay[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.day.formatted(date: .complete, time: .omitted)) {
                    ForEach(group.entries) { entry in
                        EntryLink(entry: entry)
                    }
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add one with +, or set up automatic bank messages in Settings.")
                )
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Transactions")
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
    }
}

struct ReviewView: View {
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]

    private var pending: [LedgerEntry] { entries.filter { $0.status == .needsReview } }

    var body: some View {
        List {
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { entry in
                        NavigationLink {
                            EntryEditView(mode: .review(entry))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                EntryRow(entry: entry)
                                if !entry.note.isEmpty {
                                    Text(entry.note)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Decide what each one was: an expense or income, a debt with a person, or a transfer with cash or another account.")
                }
            }
        }
        .overlay {
            if pending.isEmpty {
                ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("New CliQ transfers will show up here."))
            }
        }
        .navigationTitle("Review")
    }
}
