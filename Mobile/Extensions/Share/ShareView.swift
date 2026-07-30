import SwiftUI

struct ShareRootView: View {
    @ObservedObject var model: ShareModel
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView("Reading shared content…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "Couldn’t add to Pesty",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    form
                }
            }
            .navigationTitle("Save to Pesty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                        .disabled(!model.canSave)
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section("Items") {
                ForEach(model.drafts) { draft in
                    ShareDraftRow(draft: draft)
                }
            }

            Section("Destination") {
                Picker("Pinboard", selection: $model.selectedPinboardID) {
                    Label("History", systemImage: "clock")
                        .tag(UUID?.none)

                    ForEach(model.pinboards) { pinboard in
                        Label {
                            Text(pinboard.name)
                        } icon: {
                            Circle()
                                .fill(Color(hexString: pinboard.colorHex))
                        }
                        .tag(Optional(pinboard.id))
                    }
                }
            }

            Section {
                Text("Pesty saves this share locally and syncs it from the main app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ShareDraftRow: View {
    let draft: ShareDraft

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: draft.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(draft.displayTitle)
                    .lineLimit(2)
                if !draft.subtitle.isEmpty {
                    Text(draft.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private extension Color {
    init(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        let rgb = UInt64(value, radix: 16) ?? 0x5B8DEF
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
