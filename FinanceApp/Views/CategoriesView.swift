import SwiftData
import SwiftUI

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]
    @State private var kind: CategoryKind = .expense
    @State private var adding = false

    private var visible: [EntryCategory] { categories.filter { $0.kind == kind } }

    var body: some View {
        List {
            Section {
                Picker("Kind", selection: $kind) {
                    ForEach(CategoryKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(visible) { category in
                    NavigationLink {
                        CategoryEditView(category: category, kind: category.kind)
                    } label: {
                        Label(category.name, systemImage: category.icon)
                    }
                }
                .onDelete { offsets in
                    let items = visible
                    for index in offsets {
                        context.delete(items[index])
                    }
                    try? context.save()
                }
                .onMove { source, destination in
                    var items = visible
                    items.move(fromOffsets: source, toOffset: destination)
                    for (index, item) in items.enumerated() {
                        item.sortOrder = index
                    }
                    try? context.save()
                }
            } footer: {
                Text("Deleting a category keeps its transactions, without a category.")
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            EditButton()
            Button {
                adding = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { CategoryEditView(category: nil, kind: kind) }
        }
    }
}

struct CategoryEditView: View {
    let category: EntryCategory?
    let kind: CategoryKind

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [EntryCategory]
    @State private var name: String
    @State private var icon: String

    private static let icons = [
        "fork.knife", "cup.and.saucer", "cart", "bag", "tshirt", "gift",
        "car", "fuelpump", "bus", "airplane", "house", "bolt",
        "drop", "flame", "wifi", "phone", "cross.case", "heart",
        "pawprint", "gamecontroller", "book", "graduationcap", "wrench.and.screwdriver", "scissors",
        "briefcase", "laptopcomputer", "banknote", "creditcard", "building.columns", "arrow.uturn.backward",
        "figure.walk", "sparkles", "star", "tag", "ellipsis.circle", "questionmark.circle",
    ]

    init(category: EntryCategory?, kind: CategoryKind) {
        self.category = category
        self.kind = kind
        _name = State(initialValue: category?.name ?? "")
        _icon = State(initialValue: category?.icon ?? "tag")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
            }
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                    ForEach(Self.icons, id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(symbol == icon ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                            .onTapGesture { icon = symbol }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle(category == nil ? "New category" : "Edit category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if category == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmed.isEmpty)
            }
        }
    }

    private func save() {
        if let category {
            category.name = name.trimmed
            category.icon = icon
        } else {
            let nextOrder = (categories.filter { $0.kind == kind }.map(\.sortOrder).max() ?? -1) + 1
            context.insert(EntryCategory(name: name.trimmed, kind: kind, icon: icon, sortOrder: nextOrder))
        }
        try? context.save()
        dismiss()
    }
}
