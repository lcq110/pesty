import CloudKit
import CryptoKit
import Foundation
import Observation
import PestyShared
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

enum MobileTab: Hashable {
    case history
    case pinboards
    case stack
    case settings
}

enum MobileDateFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "Any Time"
        case .today: "Today"
        case .week: "Last 7 Days"
        case .month: "Last 30 Days"
        }
    }

    func includes(_ date: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            return date >= calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            return date >= calendar.date(byAdding: .day, value: -30, to: now)!
        }
    }
}

enum SyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case unavailable
    case failed(String)

    var label: String {
        switch self {
        case .idle: "Ready"
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .unavailable: "iCloud unavailable"
        case .failed: "Sync failed"
        }
    }
}

@Observable
@MainActor
final class MobileClipboardStore {
    static let appGroupIdentifier = "group.com.greycorelabs.pesty"
    static let cloudContainerIdentifier = "iCloud.com.greycorelabs.pesty"
    private static let preferences = UserDefaults(
        suiteName: appGroupIdentifier
    )!

    var snapshot = PestySnapshot(history: [], pinboards: [])
    var selectedTab: MobileTab = .history
    var searchText = ""
    var selectedType: ClipType?
    var selectedSourceApp: String?
    var dateFilter: MobileDateFilter = .all
    var selectedPinboardID: UUID?
    var stack: [UUID] = [] {
        didSet {
            Self.preferences.set(
                stack.map(\.uuidString),
                forKey: "pasteStack"
            )
        }
    }
    var capturePaused = false {
        didSet {
            Self.preferences.set(capturePaused, forKey: "capturePaused")
        }
    }
    var captureWhileOpen = true {
        didSet {
            Self.preferences.set(
                captureWhileOpen,
                forKey: "captureWhileOpen"
            )
            setForegroundCaptureActive(captureWhileOpen)
        }
    }
    var syncState: SyncState = .idle
    var lastError: String?

    private let localStore: SharedSnapshotStore?
    private let cloudSync: CloudKitSyncService
    private let cloudAssets: CloudKitAssetSyncService
    private let cloudSubscription: MobileCloudSubscriptionService
    private var saveTask: Task<Void, Never>?
    private var pasteboardCaptureTask: Task<Void, Never>?
    private var lastPasteboardChangeCount = 0

    init() {
        stack = Self.preferences
            .stringArray(forKey: "pasteStack")?
            .compactMap(UUID.init(uuidString:)) ?? []
        capturePaused = Self.preferences.bool(forKey: "capturePaused")
        captureWhileOpen = Self.preferences.object(
            forKey: "captureWhileOpen"
        ) as? Bool ?? true
        lastPasteboardChangeCount = UIPasteboard.general.changeCount
        localStore = try? SharedSnapshotStore(appGroupIdentifier: Self.appGroupIdentifier)
        cloudSync = CloudKitSyncService(containerIdentifier: Self.cloudContainerIdentifier)
        cloudAssets = CloudKitAssetSyncService(
            containerIdentifier: Self.cloudContainerIdentifier
        )
        cloudSubscription = MobileCloudSubscriptionService(
            containerIdentifier: Self.cloudContainerIdentifier
        )
    }

    var history: [ClipItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isFiltering = !query.isEmpty
            || selectedType != nil
            || selectedSourceApp != nil
            || dateFilter != .all
        let candidates = isFiltering ? allClips : snapshot.history

        return candidates.filter { clip in
            (selectedType == nil || clip.type == selectedType)
                && (selectedSourceApp == nil || clip.sourceAppName == selectedSourceApp)
                && dateFilter.includes(clip.createdAt)
                && (query.isEmpty || clip.mobileSearchText.contains(query))
        }
    }

    var sourceApps: [String] {
        Array(Set(allClips.compactMap(\.sourceAppName))).sorted()
    }

    var hasActiveFilters: Bool {
        selectedType != nil || selectedSourceApp != nil || dateFilter != .all
    }

    func clearFilters() {
        selectedType = nil
        selectedSourceApp = nil
        dateFilter = .all
    }

    var pinboards: [Pinboard] {
        snapshot.pinboards
    }

    var stackItems: [ClipItem] {
        stack.compactMap { id in clip(id: id) }
    }

    func start() async {
        if let cached = try? localStore?.load() {
            snapshot = cached
        }
        pruneStack()

        consumeShareOutbox()
        SpotlightIndexer.index(snapshot.history)
        try? await cloudSubscription.prepare()
        await refreshFromCloud()
    }

    func refreshFromCloud() async {
        syncState = .syncing

        do {
            snapshot = try await cloudSync.reconcile(
                snapshot,
                scope: .private,
                recordID: CloudKitSyncService.defaultSnapshotRecordID,
                historyLimit: 5_000
            )
            await refreshSharedPinboards()
            snapshot = try await cloudSync.reconcile(
                snapshot,
                scope: .private,
                recordID: CloudKitSyncService.defaultSnapshotRecordID,
                historyLimit: 5_000
            )
            _ = try await cloudAssets.sync(
                snapshot: snapshot,
                imagesDirectory: imagesDirectory,
                filesDirectory: filesDirectory
            )
            pruneStack()
            try saveLocal()
            SpotlightIndexer.index(snapshot.history)
            syncState = .synced(Date())
        } catch {
            syncState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func addText(_ text: String, source: String = "iPhone") {
        guard !capturePaused else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let type: ClipType = isLink(trimmed) ? .link : .text
        let item = ClipItem(
            type: type,
            text: text,
            sourceBundleID: "com.apple.UIKit",
            sourceAppName: source,
            createdAt: Date()
        )
        insert(item)
    }

    @discardableResult
    func insert(_ item: ClipItem) -> ClipItem {
        let now = Date()
        if let index = snapshot.history.firstIndex(where: { sameContent($0, item) }) {
            var existing = snapshot.history.remove(at: index)
            existing.createdAt = item.createdAt
            existing.updatedAt = now
            existing.sourceBundleID = item.sourceBundleID
            existing.sourceAppName = item.sourceAppName
            snapshot.history.insert(existing, at: 0)
            snapshot.updatedAt = now
            scheduleSaveAndSync()
            return existing
        }

        var updatedItem = item
        updatedItem.updatedAt = now
        snapshot.history.insert(updatedItem, at: 0)
        snapshot.updatedAt = now
        scheduleSaveAndSync()
        return updatedItem
    }

    func delete(_ item: ClipItem) {
        snapshot.deleteClip(id: item.id)
        stack.removeAll { $0 == item.id }
        scheduleSaveAndSync()
    }

    func rename(_ item: ClipItem, title: String) {
        update(item, title: title, text: item.text ?? "")
    }

    func update(_ item: ClipItem, title: String, text: String) {
        let now = Date()
        if let index = snapshot.history.firstIndex(where: { $0.id == item.id }) {
            snapshot.history[index].customTitle = title
            snapshot.history[index].text = text
            snapshot.history[index].updatedAt = now
        }

        for boardIndex in snapshot.pinboards.indices {
            if let itemIndex = snapshot.pinboards[boardIndex].items.firstIndex(where: { $0.id == item.id }) {
                snapshot.pinboards[boardIndex].items[itemIndex].customTitle = title
                snapshot.pinboards[boardIndex].items[itemIndex].text = text
                snapshot.pinboards[boardIndex].items[itemIndex].updatedAt = now
                snapshot.pinboards[boardIndex].updatedAt = now
            }
        }
        snapshot.updatedAt = now
        scheduleSaveAndSync()
    }

    func copy(_ item: ClipItem, plainText: Bool = false) {
        let pasteboard = UIPasteboard.general
        if plainText {
            pasteboard.string = item.text ?? item.colorHex ?? ""
            lastPasteboardChangeCount = pasteboard.changeCount
            return
        }

        switch item.type {
        case .image:
            if let data = imageData(for: item), let image = UIImage(data: data) {
                pasteboard.image = image
            }
        case .file:
            let urls = CloudKitAssetSyncService.resolvedFileURLs(
                for: item,
                filesDirectory: filesDirectory
            )
            pasteboard.urls = urls
        case .richText:
            if let rtfData = item.rtfData {
                pasteboard.setItems([
                    [
                        UTType.rtf.identifier: rtfData,
                        UTType.plainText.identifier: item.text ?? "",
                    ]
                ])
            } else {
                pasteboard.string = item.text ?? ""
            }
        case .text, .link:
            pasteboard.string = item.text ?? ""
        case .color:
            pasteboard.string = item.colorHex ?? ""
        }
        lastPasteboardChangeCount = pasteboard.changeCount
    }

    func setForegroundCaptureActive(_ isActive: Bool) {
        pasteboardCaptureTask?.cancel()
        pasteboardCaptureTask = nil
        guard isActive, captureWhileOpen else { return }

        pasteboardCaptureTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled else { return }
                self.capturePasteboardIfChanged()
            }
        }
    }

    func addToStack(_ item: ClipItem) {
        guard !stack.contains(item.id) else { return }
        stack.append(item.id)
    }

    func removeFromStack(_ item: ClipItem) {
        stack.removeAll { $0 == item.id }
    }

    func moveStack(from source: IndexSet, to destination: Int) {
        pruneStack()
        stack.move(fromOffsets: source, toOffset: destination)
    }

    func copyNextStackItem() {
        pruneStack()
        guard let first = stackItems.first else { return }
        copy(first)
        stack.removeFirst()
    }

    func createPinboard(name: String, colorHex: String = "#5B8DEF") {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let now = Date()
        snapshot.pinboards.append(Pinboard(name: name, colorHex: colorHex, updatedAt: now))
        snapshot.updatedAt = now
        scheduleSaveAndSync()
    }

    func renamePinboard(_ board: Pinboard, to name: String) {
        guard !isReadOnlyShared(board) else { return }
        guard let index = snapshot.pinboards.firstIndex(where: { $0.id == board.id }) else { return }
        let now = Date()
        snapshot.pinboards[index].name = name
        snapshot.pinboards[index].updatedAt = now
        snapshot.updatedAt = now
        scheduleSaveAndSync()
    }

    func deletePinboard(_ board: Pinboard) {
        guard !isReadOnlyShared(board) else { return }
        snapshot.deletePinboard(id: board.id)
        if selectedPinboardID == board.id {
            selectedPinboardID = nil
        }
        pruneStack()
        scheduleSaveAndSync()
    }

    func save(_ item: ClipItem, to board: Pinboard) {
        guard !isReadOnlyShared(board) else { return }
        guard let index = snapshot.pinboards.firstIndex(where: { $0.id == board.id }) else { return }
        guard !snapshot.pinboards[index].items.contains(where: { sameContent($0, item) }) else { return }
        let now = Date()
        var copy = item
        copy.updatedAt = now
        snapshot.pinboards[index].items.insert(copy, at: 0)
        snapshot.pinboards[index].updatedAt = now
        snapshot.updatedAt = now
        scheduleSaveAndSync()
    }

    func remove(_ item: ClipItem, from board: Pinboard) {
        guard !isReadOnlyShared(board) else { return }
        let now = Date()
        snapshot.removeClip(id: item.id, fromPinboard: board.id, at: now)
        pruneStack()
        scheduleSaveAndSync()
    }

    func share(_ board: Pinboard) async -> CKShare? {
        do {
            let boardSnapshot = snapshot.scoped(toPinboard: board.id)
            let share = try await cloudSync.sharePinboard(
                board,
                tombstones: boardSnapshot.tombstones,
                title: board.name
            )
            let recordID = CloudKitSyncService.sharedPinboardRecordID(for: board.id)
            _ = try await cloudAssets.sync(
                snapshot: boardSnapshot,
                scope: .private,
                zoneID: recordID.zoneID,
                parentRecordID: recordID,
                imagesDirectory: imagesDirectory,
                filesDirectory: filesDirectory
            )
            let reference = SharedPinboardReference(recordID: recordID)
            if upsertSharedReference(reference) {
                snapshot.updatedAt = Date()
                scheduleSaveAndSync()
            }
            return share
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await cloudSync.acceptShare(metadata)
            guard let reference = CloudKitSyncService.sharedPinboardReference(from: metadata),
                  let recordID = metadata.hierarchicalRootRecordID,
                  let sharedSnapshot = try await cloudSync.pull(
                    scope: .shared,
                    recordID: recordID
                  ) else {
                return
            }

            _ = upsertSharedReference(reference)
            snapshot = SnapshotMerger.merge(
                local: snapshot,
                remote: sharedSnapshot,
                historyLimit: 5_000
            )
            _ = try await cloudAssets.sync(
                snapshot: sharedSnapshot,
                scope: .shared,
                zoneID: recordID.zoneID,
                parentRecordID: recordID,
                imagesDirectory: imagesDirectory,
                filesDirectory: filesDirectory
            )
            try saveLocal()
            await refreshFromCloud()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func handle(_ url: URL) {
        guard url.scheme == "pesty" else { return }
        selectedTab = .history
        if url.host == "search" {
            searchText = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value ?? ""
        }
    }

    func imageData(for item: ClipItem) -> Data? {
        guard let name = item.imageFileName,
              let base = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
              ) else {
            return nil
        }
        return try? Data(contentsOf: base.appendingPathComponent("images/\(name)"))
    }

    func isReadOnlyShared(_ board: Pinboard) -> Bool {
        guard let reference = sharedReference(for: board) else { return false }
        return reference.ownerName != CKCurrentUserDefaultName
            && reference.permission != .readWrite
    }

    func isShared(_ board: Pinboard) -> Bool {
        sharedReference(for: board) != nil
    }

    func canDelete(_ board: Pinboard) -> Bool {
        guard let reference = sharedReference(for: board) else { return true }
        return reference.ownerName == CKCurrentUserDefaultName
    }

    private var groupDirectory: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )!
    }

    private var imagesDirectory: URL {
        groupDirectory.appendingPathComponent("images", isDirectory: true)
    }

    private var filesDirectory: URL {
        groupDirectory.appendingPathComponent("files", isDirectory: true)
    }

    private func refreshSharedPinboards() async {
        for reference in snapshot.sharedPinboardReferences {
            let scope: CloudDatabaseScope = reference.ownerName == CKCurrentUserDefaultName
                ? .private
                : .shared
            do {
                guard let boardID = UUID(uuidString: reference.recordName) else {
                    continue
                }
                let scopedSnapshot = snapshot.scoped(toPinboard: boardID)
                let sharedSnapshot: PestySnapshot
                if scope == .private || reference.permission == .readWrite {
                    sharedSnapshot = try await cloudSync.reconcile(
                        scopedSnapshot,
                        scope: scope,
                        recordID: reference.recordID
                    )
                } else {
                    guard let pulled = try await cloudSync.pull(
                        scope: scope,
                        recordID: reference.recordID
                    ) else {
                        continue
                    }
                    sharedSnapshot = pulled
                }
                snapshot = SnapshotMerger.merge(
                    local: snapshot,
                    remote: sharedSnapshot,
                    historyLimit: 5_000
                )
                _ = try await cloudAssets.sync(
                    snapshot: sharedSnapshot,
                    scope: scope,
                    zoneID: reference.recordID.zoneID,
                    parentRecordID: reference.recordID,
                    imagesDirectory: imagesDirectory,
                    filesDirectory: filesDirectory
                )
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func consumeShareOutbox() {
        let pending = loadPendingShareEntries()
        var legacySucceeded = true

        for record in pending.sorted(by: { $0.entry.createdAt < $1.entry.createdAt }) {
            do {
                let inserted: ClipItem
                if let existing = clip(id: record.entry.id) {
                    inserted = existing
                } else {
                    inserted = try insertShareEntry(record)
                }

                if let pinboardID = record.entry.pinboardID,
                   let board = snapshot.pinboards.first(where: { $0.id == pinboardID }) {
                    save(inserted, to: board)
                }

                try saveLocal()
                if let payloadURL = record.payloadURL {
                    try FileManager.default.removeItem(at: payloadURL)
                }
                if let receiptURL = record.receiptURL {
                    try FileManager.default.removeItem(at: receiptURL)
                }
            } catch {
                legacySucceeded = legacySucceeded && !record.isLegacy
                lastError = error.localizedDescription
            }
        }

        if legacySucceeded {
            try? Data("[]".utf8).write(
                to: groupDirectory.appendingPathComponent("share-outbox.json"),
                options: .atomic
            )
        }
    }

    private func scheduleSaveAndSync() {
        do {
            try saveLocal()
        } catch {
            lastError = error.localizedDescription
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            await refreshFromCloud()
        }
    }

    private func saveLocal() throws {
        guard let localStore else {
            throw SharedSnapshotStoreError.appGroupUnavailable(
                Self.appGroupIdentifier
            )
        }
        try localStore.save(snapshot)
    }

    private func insertShareEntry(_ record: PendingShareEntry) throws -> ClipItem {
        let entry = record.entry
        let type = ClipType(rawValue: entry.type) ?? .text
        let payload = try record.payloadURL.map { try Data(contentsOf: $0) }
            ?? entry.dataBase64.flatMap { Data(base64Encoded: $0) }
        var imageFileName: String?
        var imageHash: String?
        var fileURLs: [String] = []
        var searchableText = entry.text ?? entry.fileName

        if type == .image {
            guard let payload else { throw ShareOutboxError.missingPayload(entry.id) }
            imageFileName = try saveImagePayload(
                payload,
                id: entry.id,
                originalName: entry.fileName
            )
            imageHash = payload.sha256
            searchableText = recognizedText(in: payload) ?? entry.fileName
        } else if type == .file {
            guard let payload, let name = entry.fileName else {
                throw ShareOutboxError.missingPayload(entry.id)
            }
            fileURLs = [
                try saveFilePayload(payload, id: entry.id, name: name).absoluteString
            ]
        }

        return insert(
            ClipItem(
                id: entry.id,
                type: type,
                text: searchableText,
                imageFileName: imageFileName,
                imageHash: imageHash,
                fileURLs: fileURLs,
                sourceBundleID: "com.apple.UIKit.activity.Share",
                sourceAppName: "iOS Share Sheet",
                createdAt: entry.createdAt
            )
        )
    }

    private func loadPendingShareEntries() -> [PendingShareEntry] {
        let decoder = JSONDecoder()
        let outboxDirectory = groupDirectory.appendingPathComponent(
            "share-outbox",
            isDirectory: true
        )
        let payloadDirectory = outboxDirectory.appendingPathComponent(
            "payloads",
            isDirectory: true
        )
        let receiptURLs = (
            try? FileManager.default.contentsOfDirectory(
                at: outboxDirectory,
                includingPropertiesForKeys: nil
            )
        )?.filter { $0.pathExtension == "json" } ?? []

        var records = receiptURLs.compactMap { receiptURL -> PendingShareEntry? in
            guard let data = try? Data(contentsOf: receiptURL),
                  let entry = try? decoder.decode(ShareOutboxEntry.self, from: data) else {
                return nil
            }
            let payloadURL = entry.payloadFileName.map {
                payloadDirectory.appendingPathComponent($0)
            }
            return PendingShareEntry(
                entry: entry,
                receiptURL: receiptURL,
                payloadURL: payloadURL,
                isLegacy: false
            )
        }

        let legacyURL = groupDirectory.appendingPathComponent("share-outbox.json")
        if let data = try? Data(contentsOf: legacyURL),
           let entries = try? decoder.decode([ShareOutboxEntry].self, from: data) {
            records += entries.map {
                PendingShareEntry(
                    entry: $0,
                    receiptURL: nil,
                    payloadURL: nil,
                    isLegacy: true
                )
            }
        }
        return records
    }

    private func clip(id: UUID) -> ClipItem? {
        snapshot.history.first { $0.id == id }
            ?? snapshot.pinboards.lazy.flatMap(\.items).first { $0.id == id }
    }

    private func sharedReference(
        for board: Pinboard
    ) -> SharedPinboardReference? {
        snapshot.sharedPinboardReferences.first {
            $0.recordName == board.id.uuidString
        }
    }

    @discardableResult
    private func upsertSharedReference(
        _ reference: SharedPinboardReference
    ) -> Bool {
        if let index = snapshot.sharedPinboardReferences.firstIndex(
            where: { $0.id == reference.id }
        ) {
            guard snapshot.sharedPinboardReferences[index] != reference else {
                return false
            }
            snapshot.sharedPinboardReferences[index] = reference
            return true
        }
        snapshot.sharedPinboardReferences.append(reference)
        return true
    }

    private var allClips: [ClipItem] {
        var seen = Set<UUID>()
        return (snapshot.history + snapshot.pinboards.flatMap(\.items))
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func pruneStack() {
        let validIDs = Set(allClips.map(\.id))
        stack.removeAll { !validIDs.contains($0) }
    }

    private func capturePasteboardIfChanged() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChangeCount else {
            return
        }
        lastPasteboardChangeCount = pasteboard.changeCount
        guard !capturePaused else { return }

        if let rtfData = pasteboard.data(
            forPasteboardType: UTType.rtf.identifier
        ), let text = pasteboard.string ?? plainText(fromRTF: rtfData) {
            insert(
                ClipItem(
                    type: .richText,
                    text: text,
                    rtfData: rtfData,
                    sourceBundleID: "com.apple.UIKit",
                    sourceAppName: "iOS Clipboard"
                )
            )
        } else if let image = pasteboard.image,
                  let data = image.pngData() {
            do {
                let id = UUID()
                let imageFileName = try saveImagePayload(
                    data,
                    id: id,
                    originalName: nil
                )
                insert(
                    ClipItem(
                        id: id,
                        type: .image,
                        text: recognizedText(in: data),
                        imageFileName: imageFileName,
                        imageHash: data.sha256,
                        sourceBundleID: "com.apple.UIKit",
                        sourceAppName: "iOS Clipboard"
                    )
                )
            } catch {
                lastError = error.localizedDescription
            }
        } else if let sourceURLs = pasteboard.urls?.filter(\.isFileURL),
                  !sourceURLs.isEmpty {
            do {
                let id = UUID()
                let cachedURLs = try sourceURLs.map { sourceURL in
                    try saveFilePayload(
                        Data(contentsOf: sourceURL),
                        id: id,
                        name: sourceURL.lastPathComponent
                    )
                }
                insert(
                    ClipItem(
                        id: id,
                        type: .file,
                        fileURLs: cachedURLs.map(\.absoluteString),
                        sourceBundleID: "com.apple.UIKit",
                        sourceAppName: "iOS Clipboard"
                    )
                )
            } catch {
                lastError = error.localizedDescription
            }
        } else if let text = pasteboard.string {
            addText(text, source: "iOS Clipboard")
        }
    }

    private func plainText(fromRTF data: Data) -> String? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ).string
    }

    private func saveImagePayload(
        _ data: Data,
        id: UUID,
        originalName: String?
    ) throws -> String {
        try FileManager.default.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true
        )
        let fileExtension = originalName
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "png"
        let name = "\(id.uuidString).\(fileExtension)"
        try data.write(
            to: imagesDirectory.appendingPathComponent(name),
            options: .atomic
        )
        return name
    }

    private func saveFilePayload(_ data: Data, id: UUID, name: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: filesDirectory,
            withIntermediateDirectories: true
        )
        let url = filesDirectory.appendingPathComponent("\(id.uuidString)-\(name)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func recognizedText(in data: Data) -> String? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])

        let lines = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.isEmpty } ?? []
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func sameContent(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
        lhs.sameContent(as: rhs)
    }

    private func isLink(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https"].contains(scheme) && url.host != nil
    }
}

private struct ShareOutboxEntry: Codable {
    var id: UUID
    var type: String
    var text: String?
    var dataBase64: String?
    var payloadFileName: String?
    var fileName: String?
    var createdAt: Date
    var pinboardID: UUID?
}

private struct PendingShareEntry {
    var entry: ShareOutboxEntry
    var receiptURL: URL?
    var payloadURL: URL?
    var isLegacy: Bool
}

private enum ShareOutboxError: LocalizedError {
    case missingPayload(UUID)

    var errorDescription: String? {
        switch self {
        case .missingPayload(let id):
            "Share payload is missing for \(id.uuidString)."
        }
    }
}

private extension Data {
    var sha256: String {
        SHA256.hash(data: self)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
