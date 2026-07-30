import SwiftUI

struct StackView: View {
    @Environment(MobileClipboardStore.self) private var store

    var body: some View {
        Group {
            if store.stackItems.isEmpty {
                ContentUnavailableView {
                    Label("Stack is empty", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Add clips from History, then copy them one by one while filling forms or repeating a workflow.")
                }
            } else {
                List {
                    Section {
                        Button {
                            store.copyNextStackItem()
                        } label: {
                            Label("Copy Next Item", systemImage: "arrow.right.doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Section("Queue") {
                        ForEach(store.stackItems) { item in
                            ClipCard(item: item)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.removeFromStack(item)
                                    } label: {
                                        Label("Remove", systemImage: "minus.circle")
                                    }
                                }
                        }
                        .onMove(perform: store.moveStack)
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
        }
        .navigationTitle("Paste Stack")
        .toolbar {
            if !store.stackItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(store.stackItems.count) queued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
