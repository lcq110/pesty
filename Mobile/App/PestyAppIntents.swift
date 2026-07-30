import AppIntents
import PestyShared
import UIKit

struct OpenPestyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Pesty"
    static let description = IntentDescription("Open your synchronized clipboard history.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct CopyLatestPestyClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Latest Pesty Clip"
    static let description = IntentDescription("Copy the newest text or link from Pesty.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try SharedSnapshotStore(
            appGroupIdentifier: MobileClipboardStore.appGroupIdentifier
        )
        guard let snapshot = try store.load(),
              let text = snapshot.history.first(where: {
            [.text, .richText, .link, .color].contains($0.type)
        }).flatMap({ $0.text ?? $0.colorHex }) else {
            return .result(dialog: "Pesty has no text clips yet.")
        }

        UIPasteboard.general.string = text
        return .result(dialog: "Copied the latest Pesty clip.")
    }
}

struct PestyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPestyIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show my \(.applicationName) clipboard"
            ],
            shortTitle: "Open Pesty",
            systemImageName: "doc.on.clipboard"
        )

        AppShortcut(
            intent: CopyLatestPestyClipIntent(),
            phrases: [
                "Copy my latest \(.applicationName) clip"
            ],
            shortTitle: "Copy Latest Clip",
            systemImageName: "doc.on.doc"
        )
    }
}
