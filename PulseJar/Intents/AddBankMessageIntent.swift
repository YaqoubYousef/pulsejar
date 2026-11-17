import AppIntents
import Foundation

/// Shortcuts action used by the "When I get a message containing المبلغ" automation.
struct AddBankMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Bank Message"
    static var description = IntentDescription("Reads a bank SMS and records it as a transaction. CliQ transfers wait for your review.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add bank message \(\.$message)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let outcome = MessageIngestor.ingest(text: message, context: AppDatabase.container.mainContext)
        return .result(value: outcome.summary)
    }
}

struct PulseJarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddBankMessageIntent(),
            phrases: ["Add bank message in \(.applicationName)"],
            shortTitle: "Add Bank Message",
            systemImageName: "text.bubble"
        )
    }
}
