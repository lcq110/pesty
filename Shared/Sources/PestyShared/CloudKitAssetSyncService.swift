import CloudKit
import Foundation

public struct CloudAssetSyncResult: Equatable, Sendable {
    public var uploaded: Int
    public var downloaded: Int
    public var unavailable: Int

    public init(uploaded: Int, downloaded: Int, unavailable: Int) {
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.unavailable = unavailable
    }
}

public enum CloudKitAssetSyncError: Error {
    case missingRecordResult(CKRecord.ID)
    case missingAsset(CKRecord.ID)
}

public actor CloudKitAssetSyncService {
    public static let assetRecordType = "PestyAsset"

    private enum Field {
        static let asset = "asset"
        static let kind = "kind"
        static let fileName = "fileName"
        static let clipID = "clipID"
        static let index = "index"
    }

    private enum Kind: String {
        case image
        case file
    }

    private struct Descriptor {
        let recordID: CKRecord.ID
        let kind: Kind
        let clipID: UUID
        let index: Int
        let fileName: String
        let sourceURL: URL?
        let destinationURL: URL
    }

    private let container: CKContainer

    public init(containerIdentifier: String? = nil) {
        if let containerIdentifier {
            container = CKContainer(identifier: containerIdentifier)
        } else {
            container = .default()
        }
    }

    public func sync(
        snapshot: PestySnapshot,
        scope: CloudDatabaseScope = .private,
        zoneID: CKRecordZone.ID? = nil,
        parentRecordID: CKRecord.ID? = nil,
        imagesDirectory: URL,
        filesDirectory: URL
    ) async throws -> CloudAssetSyncResult {
        try FileManager.default.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: filesDirectory,
            withIntermediateDirectories: true
        )

        let descriptors = Self.descriptors(
            snapshot: snapshot,
            zoneID: zoneID,
            imagesDirectory: imagesDirectory,
            filesDirectory: filesDirectory
        )
        let grouped = Dictionary(grouping: descriptors, by: \.recordID)
        let recordIDs = grouped.keys.sorted { left, right in
            left.recordName < right.recordName
        }
        let database = database(for: scope)

        var uploads: [CKRecord] = []
        var downloaded = 0
        var unavailable = 0

        for batch in recordIDs.chunked(maxCount: 200) {
            let results = try await database.records(for: batch)
            for recordID in batch {
                guard let descriptors = grouped[recordID],
                      let result = results[recordID] else {
                    throw CloudKitAssetSyncError.missingRecordResult(recordID)
                }

                switch result {
                case .success(let record):
                    guard let asset = record[Field.asset] as? CKAsset,
                          let assetURL = asset.fileURL else {
                        throw CloudKitAssetSyncError.missingAsset(recordID)
                    }
                    for descriptor in descriptors
                    where descriptor.sourceURL == nil
                        && !FileManager.default.fileExists(
                            atPath: descriptor.destinationURL.path
                        ) {
                        try Self.copy(assetURL, to: descriptor.destinationURL)
                        downloaded += 1
                    }

                case .failure(let error as CKError) where error.code == .unknownItem:
                    guard let source = descriptors.compactMap(\.sourceURL).first,
                          let descriptor = descriptors.first else {
                        unavailable += descriptors.count
                        continue
                    }

                    let record = CKRecord(
                        recordType: Self.assetRecordType,
                        recordID: recordID
                    )
                    record[Field.asset] = CKAsset(fileURL: source)
                    record[Field.kind] = descriptor.kind.rawValue as CKRecordValue
                    record[Field.fileName] = descriptor.fileName as CKRecordValue
                    record[Field.clipID] = descriptor.clipID.uuidString as CKRecordValue
                    record[Field.index] = descriptor.index as CKRecordValue
                    if let parentRecordID {
                        record.parent = CKRecord.Reference(
                            recordID: parentRecordID,
                            action: .none
                        )
                    }
                    uploads.append(record)

                    for missing in descriptors
                    where missing.sourceURL == nil
                        && !FileManager.default.fileExists(
                            atPath: missing.destinationURL.path
                        ) {
                        try Self.copy(source, to: missing.destinationURL)
                        downloaded += 1
                    }

                case .failure(let error):
                    throw error
                }
            }
        }

        for batch in uploads.chunked(maxCount: 100) {
            let result = try await database.modifyRecords(
                saving: batch,
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: false
            )
            for record in batch {
                guard let saveResult = result.saveResults[record.recordID] else {
                    throw CloudKitAssetSyncError.missingRecordResult(record.recordID)
                }
                _ = try saveResult.get()
            }
        }

        return CloudAssetSyncResult(
            uploaded: uploads.count,
            downloaded: downloaded,
            unavailable: unavailable
        )
    }

    public nonisolated static func cachedFileURL(
        for item: ClipItem,
        index: Int,
        filesDirectory: URL
    ) -> URL {
        let original = modelURL(item.fileURLs[index])
        let name = original.lastPathComponent.isEmpty
            ? "File"
            : original.lastPathComponent
        return filesDirectory.appendingPathComponent(
            "\(item.id.uuidString)-\(index)-\(name)",
            isDirectory: false
        )
    }

    public nonisolated static func resolvedFileURLs(
        for item: ClipItem,
        filesDirectory: URL
    ) -> [URL] {
        item.fileURLs.enumerated().compactMap { index, value in
            let original = modelURL(value)
            if FileManager.default.fileExists(atPath: original.path) {
                return original
            }
            let cached = cachedFileURL(
                for: item,
                index: index,
                filesDirectory: filesDirectory
            )
            return FileManager.default.fileExists(atPath: cached.path)
                ? cached
                : nil
        }
    }

    private func database(for scope: CloudDatabaseScope) -> CKDatabase {
        switch scope {
        case .private:
            container.privateCloudDatabase
        case .shared:
            container.sharedCloudDatabase
        }
    }

    private nonisolated static func descriptors(
        snapshot: PestySnapshot,
        zoneID: CKRecordZone.ID?,
        imagesDirectory: URL,
        filesDirectory: URL
    ) -> [Descriptor] {
        let descriptors = (
            snapshot.history + snapshot.pinboards.flatMap(\.items)
        ).flatMap { item -> [Descriptor] in
            switch item.type {
            case .image:
                guard let fileName = item.imageFileName else {
                    return []
                }
                let destination = imagesDirectory.appendingPathComponent(fileName)
                let source = FileManager.default.fileExists(atPath: destination.path)
                    ? destination
                    : nil
                let identity = item.imageHash ?? item.id.uuidString.lowercased()
                return [
                    Descriptor(
                        recordID: recordID(
                            name: "image-\(identity)",
                            zoneID: zoneID
                        ),
                        kind: .image,
                        clipID: item.id,
                        index: 0,
                        fileName: fileName,
                        sourceURL: source,
                        destinationURL: destination
                    )
                ]

            case .file:
                return item.fileURLs.enumerated().map { index, value in
                    let original = modelURL(value)
                    let destination = cachedFileURL(
                        for: item,
                        index: index,
                        filesDirectory: filesDirectory
                    )
                    let source: URL?
                    if FileManager.default.fileExists(atPath: original.path) {
                        source = original
                    } else if FileManager.default.fileExists(atPath: destination.path) {
                        source = destination
                    } else {
                        source = nil
                    }
                    return Descriptor(
                        recordID: recordID(
                            name: "file-\(item.id.uuidString.lowercased())-\(index)",
                            zoneID: zoneID
                        ),
                        kind: .file,
                        clipID: item.id,
                        index: index,
                        fileName: original.lastPathComponent,
                        sourceURL: source,
                        destinationURL: destination
                    )
                }

            case .text, .richText, .link, .color:
                return []
            }
        }

        var seen = Set<String>()
        return descriptors.filter { descriptor in
            let zone = descriptor.recordID.zoneID
            let key = [
                zone.ownerName,
                zone.zoneName,
                descriptor.recordID.recordName,
                descriptor.destinationURL.path,
            ].joined(separator: "\u{1F}")
            return seen.insert(key).inserted
        }
    }

    private nonisolated static func recordID(
        name: String,
        zoneID: CKRecordZone.ID?
    ) -> CKRecord.ID {
        if let zoneID {
            return CKRecord.ID(recordName: name, zoneID: zoneID)
        }
        return CKRecord.ID(recordName: name)
    }

    private nonisolated static func modelURL(_ value: String) -> URL {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: value)
    }

    private nonisolated static func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start..<Swift.min(start + maxCount, count)])
        }
    }
}
