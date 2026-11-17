import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var exportDocument: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingBackup: BackupFile?
    @State private var message: String?

    private var backupFilename: String {
        "finance-backup-\(Date.now.formatted(.iso8601.year().month().day()))"
    }

    var body: some View {
        List {
            Section("Bank messages") {
                NavigationLink {
                    ShortcutsGuideView()
                } label: {
                    Label("Record messages automatically", systemImage: "bolt.badge.automatic")
                }
                NavigationLink {
                    PasteMessagesView()
                } label: {
                    Label("Paste bank messages", systemImage: "doc.on.clipboard")
                }
                NavigationLink {
                    MerchantRulesView()
                } label: {
                    Label("Merchant categories", systemImage: "storefront")
                }
            }

            Section("Organize") {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "tag")
                }
            }

            Section {
                Button {
                    do {
                        exportDocument = BackupDocument(data: try Backup.export(context: context))
                        exporting = true
                    } catch {
                        message = "Export failed: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Export backup", systemImage: "square.and.arrow.up")
                }
                Button {
                    importing = true
                } label: {
                    Label("Restore from backup", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Everything is stored only on this iPhone. Export a backup to Files now and then — deleting the app deletes its data.")
            }

            Section {
                MakerFooter()
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: backupFilename) { result in
            if case .failure(let error) = result {
                message = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                pendingBackup = try Backup.decode(try Data(contentsOf: url))
            } catch {
                message = "Couldn't read the backup: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Replace all data with this backup?",
            isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace everything", role: .destructive) {
                guard let backup = pendingBackup else {
                    return
                }
                do {
                    try Backup.restore(backup, context: context)
                    MessageIngestor.refreshBadge(context)
                    message = "Backup restored."
                } catch {
                    message = "Restore failed: \(error.localizedDescription)"
                }
                pendingBackup = nil
            }
        } message: {
            if let backup = pendingBackup {
                Text("Backup from \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)) with \(backup.entries.count) transactions. Current data will be deleted.")
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

struct ShortcutsGuideView: View {
    var body: some View {
        List {
            Section {
                step(1, "Open this app once, so iPhone learns its Shortcuts action.")
                step(2, "Open the Shortcuts app → Automation → + → Message.")
                step(3, "Leave Sender empty. Set Message Contains to  المبلغ")
                step(4, "Choose Run Immediately, then Next.")
                step(5, "Tap New Blank Automation → Add Action, search for \"Add Bank Message\" and pick it.")
                step(6, "Tap the Message field and choose Shortcut Input (the message content). Tap Done.")
            } header: {
                Text("One-time setup")
            } footer: {
                Text("Every bank SMS is now recorded. Purchases and salary are saved directly; CliQ transfers wait in Review. Messages that aren't bank transactions are ignored.")
            }
            Section("Tips") {
                Text("If your bank sends English messages too, add a second automation with a word they always contain, such as JOD.")
                Text("Old messages can be added with Settings → Paste bank messages. Duplicates are ignored.")
            }
        }
        .navigationTitle("Automatic recording")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}

struct PasteMessagesView: View {
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var outcomes: [IngestOutcome] = []

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 200)
                    .environment(\.layoutDirection, .rightToLeft)
            } footer: {
                Text("Paste one or many bank messages. They're processed oldest first, and messages already recorded are skipped.")
            }
            Section {
                Button("Add messages") {
                    outcomes = MessageIngestor.ingestMany(text: text, context: context)
                    text = ""
                }
                .disabled(text.trimmed.isEmpty)
            }
            if !outcomes.isEmpty {
                Section("Result") {
                    ForEach(outcomes) { outcome in
                        Label(outcome.summary, systemImage: icon(for: outcome.status))
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Paste bank messages")
    }

    private func icon(for status: IngestOutcome.Status) -> String {
        switch status {
        case .recorded: return "checkmark.circle"
        case .needsReview: return "exclamationmark.bubble"
        case .reversed: return "arrow.uturn.backward.circle"
        case .duplicate: return "equal.circle"
        case .notRecognized: return "questionmark.circle"
        }
    }
}

struct MerchantRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MerchantRule.merchant) private var rules: [MerchantRule]

    var body: some View {
        List {
            ForEach(rules) { rule in
                LabeledContent(rule.merchant.capitalized, value: rule.category?.name ?? "—")
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(rules[index])
                }
                try? context.save()
            }
        }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView(
                    "No merchant categories yet",
                    systemImage: "storefront",
                    description: Text("When you categorize a purchase, the app remembers the merchant and files its next purchases automatically.")
                )
            }
        }
        .navigationTitle("Merchant categories")
    }
}
