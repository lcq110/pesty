import PestyShared
import SwiftUI

struct ClipDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MobileClipboardStore.self) private var store

    let item: ClipItem
    @State private var title: String
    @State private var text: String

    init(item: ClipItem) {
        self.item = item
        _title = State(initialValue: item.customTitle ?? "")
        _text = State(initialValue: item.text ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    ClipCard(item: item)
                }

                Section("Title") {
                    TextField("Optional title", text: $title)
                }

                if item.type != .file && item.type != .color {
                    Section(item.type == .image ? "Recognized Text" : "Content") {
                        TextEditor(text: $text)
                            .frame(minHeight: 150)
                    }
                }

                Section("Actions") {
                    Button {
                        store.copy(item)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Button {
                        store.addToStack(item)
                    } label: {
                        Label("Add to Paste Stack", systemImage: "square.stack.3d.up")
                    }

                    if let shareText = item.text ?? item.colorHex {
                        ShareLink(item: shareText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Metadata") {
                    LabeledContent("Type", value: PestyTheme.label(for: item.type))
                    if let source = item.sourceAppName {
                        LabeledContent("Source", value: source)
                    }
                    LabeledContent("Created") {
                        Text(item.createdAt, format: .dateTime)
                    }
                }
            }
            .navigationTitle("Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(item, title: title, text: text)
                        dismiss()
                    }
                }
            }
        }
    }
}
