import CloudKit
import PestyShared
import SwiftUI

struct PinboardsView: View {
    @Environment(MobileClipboardStore.self) private var store
    @State private var showingNewBoard = false
    @State private var newBoardName = ""

    var body: some View {
        Group {
            if store.pinboards.isEmpty {
                ContentUnavailableView {
                    Label("No Pinboards", systemImage: "pin")
                } description: {
                    Text("Create a collection for snippets, links, images, and templates you reuse.")
                } actions: {
                    Button("Create Pinboard") {
                        showingNewBoard = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(store.pinboards) { board in
                        NavigationLink(value: board.id) {
                            PinboardRow(
                                board: board,
                                isShared: store.isShared(board)
                            )
                        }
                        .swipeActions {
                            if store.canDelete(board) {
                                Button(role: .destructive) {
                                    store.deletePinboard(board)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let board = store.pinboards.first(where: { $0.id == id }) {
                        PinboardDetailView(boardID: board.id)
                    } else {
                        ContentUnavailableView("Pinboard unavailable", systemImage: "pin.slash")
                    }
                }
            }
        }
        .navigationTitle("Pinboards")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewBoard = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Pinboard")
            }
        }
        .alert("New Pinboard", isPresented: $showingNewBoard) {
            TextField("Name", text: $newBoardName)
            Button("Cancel", role: .cancel) {
                newBoardName = ""
            }
            Button("Create") {
                store.createPinboard(name: newBoardName)
                newBoardName = ""
            }
        } message: {
            Text("Pinboards sync with your Macs and stay available in Pesty Keyboard.")
        }
    }
}

private struct PinboardRow: View {
    let board: Pinboard
    let isShared: Bool

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hexString: board.colorHex) ?? PestyTheme.tint)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(board.name)
                    .font(.headline)
                HStack(spacing: 5) {
                    Text("\(board.items.count) items")
                    if isShared {
                        Label("Shared", systemImage: "person.2.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct PinboardDetailView: View {
    @Environment(MobileClipboardStore.self) private var store
    let boardID: UUID

    @State private var showingRename = false
    @State private var editedName = ""
    @State private var sharePresentation: SharePresentation?
    @State private var preparingShare = false
    @State private var selectedItem: ClipItem?

    private var board: Pinboard? {
        store.pinboards.first { $0.id == boardID }
    }

    var body: some View {
        Group {
            if let board {
                if board.items.isEmpty {
                    ContentUnavailableView {
                        Label("Empty Pinboard", systemImage: "pin")
                    } description: {
                        Text("Save clips here from History or the iOS Share Sheet.")
                    }
                } else {
                    List {
                        ForEach(board.items) { item in
                            ClipCard(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedItem = item
                                }
                                .swipeActions {
                                    if !store.isReadOnlyShared(board) {
                                        Button(role: .destructive) {
                                            store.remove(item, from: board)
                                        } label: {
                                            Label("Remove", systemImage: "pin.slash")
                                        }
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        store.copy(item)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }

                                    Button {
                                        store.addToStack(item)
                                    } label: {
                                        Label("Add to Stack", systemImage: "square.stack.3d.up")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle(board?.name ?? "Pinboard")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let board, !store.isReadOnlyShared(board) {
                    Button {
                        editedName = board.name
                        showingRename = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    if !store.isShared(board) {
                        Button {
                            preparingShare = true
                            Task {
                                if let share = await store.share(board) {
                                    sharePresentation = SharePresentation(share: share)
                                }
                                preparingShare = false
                            }
                        } label: {
                            if preparingShare {
                                ProgressView()
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                            }
                        }
                        .disabled(preparingShare)
                        .accessibilityLabel("Share Pinboard")
                    }
                }
            }
        }
        .alert("Rename Pinboard", isPresented: $showingRename) {
            TextField("Name", text: $editedName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let board {
                    store.renamePinboard(board, to: editedName)
                }
            }
        }
        .sheet(item: $sharePresentation) { presentation in
            CloudSharingView(share: presentation.share)
        }
        .sheet(item: $selectedItem) { item in
            ClipDetailView(item: item)
        }
    }
}

struct PinTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MobileClipboardStore.self) private var store
    let item: ClipItem

    var body: some View {
        let writablePinboards = store.pinboards.filter {
            !store.isReadOnlyShared($0)
        }

        NavigationStack {
            List(writablePinboards) { board in
                Button {
                    store.save(item, to: board)
                    dismiss()
                } label: {
                    PinboardRow(board: board, isShared: false)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if writablePinboards.isEmpty {
                    ContentUnavailableView(
                        "No Pinboards",
                        systemImage: "pin",
                        description: Text("Create a Pinboard first.")
                    )
                }
            }
            .navigationTitle("Save to Pinboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: MobileClipboardStore.cloudContainerIdentifier))
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPublic]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}

private struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
}
