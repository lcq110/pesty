import PestyShared
import SwiftUI

struct HistoryView: View {
    @Environment(MobileClipboardStore.self) private var store
    @State private var renamedItem: ClipItem?
    @State private var editedTitle = ""
    @State private var pinTarget: ClipItem?
    @State private var selectedItem: ClipItem?

    var body: some View {
        @Bindable var store = store

        mainContent
        .navigationTitle("Pesty")
        .searchable(text: $store.searchText, prompt: "Search clips, apps, and links")
        .toolbar { historyToolbar }
        .alert("Rename Clip", isPresented: Binding(
            get: { renamedItem != nil },
            set: { if !$0 { renamedItem = nil } }
        )) {
            TextField("Title", text: $editedTitle)
            Button("Cancel", role: .cancel) {
                renamedItem = nil
            }
            Button("Save") {
                if let renamedItem {
                    store.rename(renamedItem, title: editedTitle)
                }
                renamedItem = nil
            }
        }
        .sheet(item: $pinTarget) { item in
            PinTargetSheet(item: item)
        }
        .sheet(item: $selectedItem) { item in
            ClipDetailView(item: item)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if store.history.isEmpty {
            ContentUnavailableView {
                Label("No clips yet", systemImage: "doc.on.clipboard")
            } description: {
                Text("Copy on your Mac, use Save to Pesty from the Share Sheet, or import text below.")
            } actions: {
                PasteButton(payloadType: String.self) { values in
                    values.forEach { store.addText($0, source: "iOS Clipboard") }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            historyList
        }
    }

    private var historyList: some View {
        List {
            Section {
                typeFilters
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(store.history) { item in
                    clipRow(item)
                }
            } header: {
                HStack {
                    Text("\(store.history.count) clips")
                    Spacer()
                    SyncBadge(state: store.syncState)
                }
            }
        }
        .listStyle(.plain)
    }

    private func clipRow(_ item: ClipItem) -> some View {
        ClipCard(item: item)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedItem = item
            }
            .contextMenu {
                Button {
                    store.copy(item)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    store.copy(item, plainText: true)
                } label: {
                    Label("Copy as Plain Text", systemImage: "textformat")
                }

                Button {
                    store.addToStack(item)
                } label: {
                    Label("Add to Stack", systemImage: "square.stack.3d.up")
                }

                Button {
                    pinTarget = item
                } label: {
                    Label("Save to Pinboard", systemImage: "pin")
                }

                Button {
                    editedTitle = item.customTitle ?? item.mobileTitle
                    renamedItem = item
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    store.delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    store.copy(item)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .tint(PestyTheme.tint)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    store.delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    pinTarget = item
                } label: {
                    Label("Pin", systemImage: "pin")
                }
                .tint(PestyTheme.secondaryTint)
            }
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            PasteButton(payloadType: String.self) { values in
                values.forEach { store.addText($0, source: "iOS Clipboard") }
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Import clipboard text")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(
                    "Date",
                    selection: Binding(
                        get: { store.dateFilter },
                        set: { store.dateFilter = $0 }
                    )
                ) {
                    ForEach(MobileDateFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }

                Menu("Source App") {
                    Button {
                        store.selectedSourceApp = nil
                    } label: {
                        HStack {
                            Text("All Apps")
                            if store.selectedSourceApp == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(store.sourceApps, id: \.self) { source in
                        Button {
                            store.selectedSourceApp = source
                        } label: {
                            HStack {
                                Text(source)
                                if store.selectedSourceApp == source {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                if store.hasActiveFilters {
                    Divider()
                    Button("Clear Filters", role: .destructive) {
                        store.clearFilters()
                    }
                }
            } label: {
                Image(systemName: store.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter clips")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await store.refreshFromCloud() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .disabled(store.syncState == .syncing)
            .accessibilityLabel("Sync now")
        }
    }

    private var typeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    symbol: "square.grid.2x2",
                    isSelected: store.selectedType == nil
                ) {
                    store.selectedType = nil
                }

                ForEach(ClipType.allCases, id: \.self) { type in
                    FilterChip(
                        title: PestyTheme.label(for: type),
                        symbol: PestyTheme.symbol(for: type),
                        isSelected: store.selectedType == type
                    ) {
                        store.selectedType = type
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? PestyTheme.tint : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

struct SyncBadge: View {
    let state: SyncState

    var body: some View {
        HStack(spacing: 5) {
            if state == .syncing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: symbol)
            }
            Text(state.label)
        }
        .font(.caption)
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch state {
        case .synced: "checkmark.icloud.fill"
        case .failed, .unavailable: "exclamationmark.icloud.fill"
        default: "icloud"
        }
    }

    private var color: Color {
        switch state {
        case .synced: .green
        case .failed, .unavailable: .orange
        default: .secondary
        }
    }
}
