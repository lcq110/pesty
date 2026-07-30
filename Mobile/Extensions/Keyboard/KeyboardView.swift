import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var store: KeyboardStore
    let hasFullAccess: Bool
    let onAdvanceToNextKeyboard: () -> Void
    let onCommit: (KeyboardClip) -> String

    @State private var actionHint: String?

    var body: some View {
        VStack(spacing: 8) {
            header
            sourcePicker

            if let errorMessage = store.errorMessage {
                ContentUnavailableView(
                    "Pesty is not ready",
                    systemImage: "rectangle.stack.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else if store.visibleItems.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                clipList
            }

            statusBar
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onAdvanceToNextKeyboard) {
                Image(systemName: "globe")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Next keyboard")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clips", text: $store.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reload Pesty")
        }
    }

    private var sourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                sourceButton(
                    title: "History",
                    color: .accentColor,
                    source: .history
                )

                ForEach(store.pinboards) { pinboard in
                    sourceButton(
                        title: pinboard.name,
                        color: Color(hexString: pinboard.colorHex),
                        source: .pinboard(pinboard.id)
                    )
                }
            }
        }
    }

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.visibleItems) { clip in
                    Button {
                        actionHint = onCommit(clip)
                    } label: {
                        KeyboardClipRow(clip: clip)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if let actionHint {
            Label(actionHint, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        } else if !hasFullAccess {
            Label(
                "Enable Full Access to copy images, files, and rich text.",
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
        } else {
            Text("Text and links insert directly. Other clips are copied.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
    }

    private func sourceButton(
        title: String,
        color: Color,
        source: KeyboardSource
    ) -> some View {
        Button {
            store.source = source
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                store.source == source ? Color.accentColor.opacity(0.16) : Color.clear,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct KeyboardClipRow: View {
    let clip: KeyboardClip

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: clip.symbolName)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text([clip.typeLabel, clip.sourceAppName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: clip.type == "text" || clip.type == "link"
                  ? "arrow.turn.down.left"
                  : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 45)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
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
