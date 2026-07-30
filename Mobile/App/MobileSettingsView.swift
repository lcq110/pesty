import SwiftUI
import UIKit

struct MobileSettingsView: View {
    @Environment(MobileClipboardStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Form {
            Section("Sync") {
                LabeledContent("iCloud") {
                    SyncBadge(state: store.syncState)
                }

                Button {
                    Task { await store.refreshFromCloud() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.syncState == .syncing)

                Text("History and Pinboards use your private iCloud container. Shared Pinboards use CloudKit sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                Toggle("Pause Capture", isOn: $store.capturePaused)
                Toggle("Capture While Pesty Is Open", isOn: $store.captureWhileOpen)

                PasteButton(payloadType: String.self) { values in
                    values.forEach { store.addText($0, source: "iOS Clipboard") }
                }

                Text("Pesty can watch the clipboard while its window is active after you grant Apple’s paste permission. In the background, use this control, the Share Sheet, or Pesty Keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pesty Keyboard") {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("Open Keyboard Settings", systemImage: "keyboard")
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("Add Pesty Keyboard in Settings", systemImage: "1.circle.fill")
                    Label("Allow Full Access for live sync and images", systemImage: "2.circle.fill")
                    Label("Hold the globe key to switch keyboards", systemImage: "3.circle.fill")
                }
                .font(.subheadline)
            }

            Section("Privacy") {
                Label("No Pesty-operated server", systemImage: "lock.shield")
                Label("Private clips stay in your iCloud account", systemImage: "icloud")
                Label("Secure text fields always use Apple’s keyboard", systemImage: "ellipsis.rectangle")

                Text("Full Access lets the keyboard read the App Group cache. Keystrokes are never uploaded by Pesty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Device Limits") {
                Text("Mac keeps automatic background capture and direct paste. iPhone and iPad use explicit capture, Share Sheet, drag and drop, and the keyboard because iOS does not expose Mac-style global clipboard monitoring or Accessibility paste injection.")
                    .font(.footnote)
            }

            if let error = store.lastError {
                Section("Last Sync Error") {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
