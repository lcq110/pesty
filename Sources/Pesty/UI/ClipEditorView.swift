import SwiftUI

struct ClipEditorView: View {
    let item: ClipItem
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool
    @State private var text: String

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _text = State(initialValue: item.text ?? "")
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text != item.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit as New Card")
                    .font(.title2.weight(.semibold))
                Text("The original card will stay unchanged.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(size: 14))
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.fieldBG, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.cardBorder)
                }

            HStack {
                Text("\(text.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save as New Card") {
                    onSave(text)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560, height: 380)
        .onAppear { editorFocused = true }
    }
}
