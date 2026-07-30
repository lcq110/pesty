import AppKit
import Observation
import PestyShared

enum BarSource: Equatable {
    case history
    case pinboard(UUID)
}

@Observable
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var history: [ClipItem] = []
    private(set) var pinboards: [Pinboard] = []
    private(set) var sharedPinboardReferences: [SharedPinboardReference] = []
    private(set) var tombstones: [Tombstone] = []

    var source: BarSource = .history
    var searchText: String = ""
    var selectedID: UUID?

    var historyLimit: Int {
        get { Settings.shared.historyLimit }
        set { Settings.shared.historyLimit = newValue; trimHistory() }
    }

    private var storeURL: URL
    private var imagesDir: URL
    private var filesDir: URL
    private var baseDir: URL
    private var saveWorkItem: DispatchWorkItem?
    private var cloudSyncTask: Task<Void, Never>?
    private var cloudPollTask: Task<Void, Never>?
    private let cloudKit = PestyCloudKitBridge()

    private var fileWatch: DispatchSourceFileSystemObject?
    private var ignoreWatchUntil: Date = .distantPast

    static var localBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pesty", isDirectory: true)
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var iCloudBase: URL? {
        guard !isSandboxed else { return nil }
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: p.path) else { return nil }
        return p.appendingPathComponent("Pesty", isDirectory: true)
    }

    var iCloudAvailable: Bool {
        ClipboardStore.isSandboxed || ClipboardStore.iCloudBase != nil
    }

    private init() {
        let base = (Settings.shared.iCloudSync ? ClipboardStore.iCloudBase : nil) ?? ClipboardStore.localBase
        baseDir = base
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        filesDir = base.appendingPathComponent("files", isDirectory: true)
        storeURL = base.appendingPathComponent("store.json")
        prepareDirectories()
        load()
        if Settings.shared.iCloudSync {
            startWatching()
            scheduleCloudSync(immediate: true)
            startCloudPolling()
        }
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: filesDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDir.path)
    }

    var visibleItems: [ClipItem] {
        let base: [ClipItem]
        switch source {
        case .history:
            base = history
        case .pinboard(let id):
            base = pinboards.first(where: { $0.id == id })?.items ?? []
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.searchableText.contains(q) }
    }

    var selectedItem: ClipItem? {
        guard let id = selectedID else { return nil }
        return visibleItems.first(where: { $0.id == id })
    }

    func addCaptured(_ item: ClipItem) {
        if let idx = history.firstIndex(where: { $0.sameContent(as: item) }) {
            if item.imageFileName != history[idx].imageFileName { deleteImageFile(item) }
            var existing = history.remove(at: idx)
            existing.createdAt = item.createdAt
            existing.updatedAt = item.updatedAt
            history.insert(existing, at: 0)
            if source == .history && searchText.isEmpty { selectedID = existing.id }
            scheduleSave()
            return
        }
        history.insert(item, at: 0)
        trimHistory()
        if source == .history && searchText.isEmpty {
            selectedID = item.id
        }
        scheduleSave()
    }

    func applyHistoryLimit() { trimHistory(); scheduleSave() }

    private func trimHistory() {
        guard history.count > historyLimit else { return }
        let removed = Array(history[historyLimit...])
        let removedAt = Date()
        var snapshot = currentSnapshot
        for item in removed {
            snapshot.removeClipFromHistory(id: item.id, at: removedAt)
        }
        apply(snapshot)
        for item in removed { deleteImageFile(item) }
    }

    func delete(_ item: ClipItem) {
        var snapshot = currentSnapshot
        snapshot.deleteClip(id: item.id)
        apply(snapshot)
        deleteImageFile(item)
        if selectedID == item.id { selectFirst() }
        scheduleSave()
    }

    func clearHistory() {
        let old = history
        var snapshot = currentSnapshot
        snapshot.clearHistory()
        apply(snapshot)
        selectedID = nil
        for item in old { deleteImageFile(item) }
        scheduleSave()
    }

    @discardableResult
    func addPinboard(name: String, colorHex: String = "#5B8DEF") -> Pinboard {
        let b = Pinboard(name: name, colorHex: colorHex)
        pinboards.append(b)
        scheduleSave()
        return b
    }

    func renamePinboard(_ id: UUID, to name: String) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[i].name = name
        pinboards[i].updatedAt = Date()
        scheduleSave()
    }

    func deletePinboard(_ id: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        if case .pinboard(let cur) = source, cur == id { source = .history }
        let removedItems = pinboards[i].items
        var snapshot = currentSnapshot
        snapshot.deletePinboard(id: id)
        apply(snapshot)
        for item in removedItems { deleteImageFile(item) }
        scheduleSave()
    }

    func saveToPinboard(_ item: ClipItem, boardID: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == boardID }) else { return }
        if pinboards[i].items.contains(where: { $0.sameContent(as: item) }) { return }
        var copy = item
        let addedAt = Date()
        copy.updatedAt = addedAt
        if let dup = duplicateImageFile(item) { copy.imageFileName = dup }
        pinboards[i].items.insert(copy, at: 0)
        pinboards[i].updatedAt = addedAt
        scheduleSave()
    }

    func setTitle(_ title: String, for item: ClipItem) {
        let updatedAt = Date()
        if let i = history.firstIndex(where: { $0.id == item.id }) {
            history[i].customTitle = title
            history[i].updatedAt = updatedAt
        }
        for b in pinboards.indices {
            if let i = pinboards[b].items.firstIndex(where: { $0.id == item.id }) {
                pinboards[b].items[i].customTitle = title
                pinboards[b].items[i].updatedAt = updatedAt
            }
        }
        scheduleSave()
    }

    func selectFirst() { selectedID = visibleItems.first?.id }

    func moveSelection(by delta: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else {
            selectedID = items.first?.id; return
        }
        let next = max(0, min(items.count - 1, idx + delta))
        selectedID = items[next].id
    }

    func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func loadImage(for item: ClipItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    func resolvedFileURLs(for item: ClipItem) -> [URL] {
        CloudKitAssetSyncService.resolvedFileURLs(
            for: item,
            filesDirectory: filesDir
        )
    }

    func storeImageData(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).png"
        let url = imagesDir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return name
        } catch { return nil }
    }

    private func duplicateImageFile(_ item: ClipItem) -> String? {
        guard let src = imageURL(for: item), FileManager.default.fileExists(atPath: src.path) else { return nil }
        let name = "\(UUID().uuidString).png"
        let dst = imagesDir.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            return name
        } catch {
            return nil
        }
    }

    private func deleteImageFile(_ item: ClipItem) {
        guard let name = item.imageFileName else { return }
        let stillUsed = history.contains { $0.imageFileName == name }
            || pinboards.contains { $0.items.contains { $0.imageFileName == name } }
        if stillUsed { return }
        if let url = imageURL(for: item) { try? FileManager.default.removeItem(at: url) }
    }

    private var currentSnapshot: PestySnapshot {
        PestySnapshot(
            history: history,
            pinboards: pinboards,
            sharedPinboardReferences: sharedPinboardReferences,
            tombstones: tombstones
        )
    }

    private func apply(_ snapshot: PestySnapshot) {
        history = snapshot.history
        pinboards = snapshot.pinboards
        sharedPinboardReferences = snapshot.sharedPinboardReferences
        tombstones = snapshot.tombstones
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(PestySnapshot.self, from: data) else { return }
        apply(snapshot)
        selectFirst()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        writeSnapshotToDisk()
        scheduleCloudSync()
    }

    private func writeSnapshotToDisk() {
        guard let data = try? JSONEncoder().encode(currentSnapshot) else { return }
        ignoreWatchUntil = Date().addingTimeInterval(1.5)
        try? data.write(to: storeURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }

    func setICloudSync(_ enabled: Bool) {
        stopWatching()
        let target = (enabled ? ClipboardStore.iCloudBase : ClipboardStore.localBase) ?? ClipboardStore.localBase
        let newImages = target.appendingPathComponent("images", isDirectory: true)
        let newFiles = target.appendingPathComponent("files", isDirectory: true)
        let newStore = target.appendingPathComponent("store.json")
        let fm = FileManager.default
        try? fm.createDirectory(at: newImages, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: newFiles, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        if fm.fileExists(atPath: newStore.path),
           let data = try? Data(contentsOf: newStore),
           let snapshot = try? JSONDecoder().decode(PestySnapshot.self, from: data) {
            copyImages(from: imagesDir, to: newImages)
            copyFiles(from: filesDir, to: newFiles)
            baseDir = target; imagesDir = newImages; filesDir = newFiles; storeURL = newStore
            mergeExternal(snapshot)
        } else {
            copyImages(from: imagesDir, to: newImages)
            copyFiles(from: filesDir, to: newFiles)
            baseDir = target; imagesDir = newImages; filesDir = newFiles; storeURL = newStore
            saveNow()
        }
        prepareDirectories()
        if enabled {
            startWatching()
            scheduleCloudSync(immediate: true)
            startCloudPolling()
        } else {
            cloudSyncTask?.cancel()
            cloudSyncTask = nil
            cloudPollTask?.cancel()
            cloudPollTask = nil
        }
    }

    private func copyImages(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "png" {
            let target = dst.appendingPathComponent(f.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: f, to: target) }
        }
    }

    private func copyFiles(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path) {
                try? fileManager.copyItem(at: file, to: target)
            }
        }
    }

    private func mergeExternal(_ snapshot: PestySnapshot) {
        let local = currentSnapshot
        let merged = SnapshotMerger.merge(
            local: local,
            remote: snapshot,
            historyLimit: historyLimit
        )
        guard merged != local else { return }
        apply(merged)
        selectFirst()
        saveNow()
    }

    private func scheduleCloudSync(immediate: Bool = false) {
        guard Settings.shared.iCloudSync else { return }
        cloudSyncTask?.cancel()

        let local = currentSnapshot
        let imagesDirectory = imagesDir
        let filesDirectory = filesDir
        let cloudKit = cloudKit
        cloudSyncTask = Task { [weak self] in
            do {
                if !immediate {
                    try await Task.sleep(for: .milliseconds(700))
                }
                try Task.checkCancellation()
                let cloudSnapshot = try await cloudKit.reconcile(
                    local: local,
                    imagesDirectory: imagesDirectory,
                    filesDirectory: filesDirectory
                )
                try Task.checkCancellation()
                guard let self else { return }

                let current = self.currentSnapshot
                let merged = SnapshotMerger.merge(
                    local: current,
                    remote: cloudSnapshot,
                    historyLimit: self.historyLimit
                )
                guard merged != current else { return }
                self.apply(merged)
                self.selectFirst()
                self.writeSnapshotToDisk()
            } catch is CancellationError {
                return
            } catch {
                NSLog("Pesty CloudKit sync failed: %@", error.localizedDescription)
            }
        }
    }

    private func startCloudPolling() {
        cloudPollTask?.cancel()
        cloudPollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard let self else { return }
                self.scheduleCloudSync(immediate: true)
            }
        }
    }

    private func startWatching() {
        stopWatching()
        let fd = open(storeURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if Date() < self.ignoreWatchUntil { return }
            if let data = try? Data(contentsOf: self.storeURL),
               let snapshot = try? JSONDecoder().decode(PestySnapshot.self, from: data) {
                self.mergeExternal(snapshot)
            }
            self.startWatching()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileWatch = src
    }

    private func stopWatching() {
        fileWatch?.cancel()
        fileWatch = nil
    }
}
