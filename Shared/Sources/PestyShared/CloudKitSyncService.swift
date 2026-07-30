import CloudKit
import Foundation

public enum CloudDatabaseScope: String, Codable, CaseIterable, Sendable {
    case `private`
    case shared

    public static var privateDatabase: Self { .private }
    public static var sharedDatabase: Self { .shared }
}

public enum CloudKitSyncError: Error {
    case missingRecordResult(CKRecord.ID)
    case missingSnapshotPayload(CKRecord.ID)
    case conflictRetriesExhausted(CKRecord.ID)
}

public extension SharedPinboardReference {
    init(recordID: CKRecord.ID) {
        self.init(
            recordName: recordID.recordName,
            zoneName: recordID.zoneID.zoneName,
            ownerName: recordID.zoneID.ownerName,
            permission: recordID.zoneID.ownerName == CKCurrentUserDefaultName
                ? .owner
                : .readOnly
        )
    }

    var recordID: CKRecord.ID {
        CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(
                zoneName: zoneName,
                ownerName: ownerName
            )
        )
    }
}

enum CloudKitSnapshotPayload {
    static let legacyDataField = "payload"
    static let assetField = "payloadAsset"

    static func attach(
        _ snapshot: PestySnapshot,
        to record: CKRecord
    ) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PestySnapshot-\(UUID().uuidString).json",
                isDirectory: false
            )
        try SnapshotCoding.encoder.encode(snapshot)
            .write(to: fileURL, options: .atomic)
        record[assetField] = CKAsset(fileURL: fileURL)
        record[legacyDataField] = nil
        return fileURL
    }

    static func decode(from record: CKRecord) throws -> PestySnapshot {
        if let asset = record[assetField] as? CKAsset,
           let fileURL = asset.fileURL {
            return try SnapshotCoding.decoder.decode(
                PestySnapshot.self,
                from: Data(contentsOf: fileURL)
            )
        }
        if let data = record[legacyDataField] as? Data {
            return try SnapshotCoding.decoder.decode(
                PestySnapshot.self,
                from: data
            )
        }
        throw CloudKitSyncError.missingSnapshotPayload(record.recordID)
    }
}

public actor CloudKitSyncService {
    public static let snapshotRecordType = "PestySnapshot"
    public static let defaultSnapshotRecordName = "primary"
    public static let defaultSnapshotRecordID = CKRecord.ID(
        recordName: defaultSnapshotRecordName
    )
    public static let sharedPinboardsZoneName = "PestySharedPinboards"
    public static var sharedPinboardsZoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: sharedPinboardsZoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    public static func sharedPinboardRecordID(for pinboardID: UUID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: pinboardID.uuidString,
            zoneID: sharedPinboardsZoneID
        )
    }

    public static func sharedPinboardReference(
        from metadata: CKShare.Metadata
    ) -> SharedPinboardReference? {
        guard let recordID = metadata.hierarchicalRootRecordID else {
            return nil
        }
        var reference = SharedPinboardReference(recordID: recordID)
        switch metadata.participantPermission {
        case .readWrite:
            reference.permission = .readWrite
        case .readOnly:
            reference.permission = .readOnly
        default:
            break
        }
        return reference
    }

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let updatedAt = "updatedAt"
    }

    private let container: CKContainer

    public init(containerIdentifier: String? = nil) {
        if let containerIdentifier {
            container = CKContainer(identifier: containerIdentifier)
        } else {
            container = .default()
        }
    }

    public func pull(
        scope: CloudDatabaseScope = .private,
        recordID: CKRecord.ID? = nil
    ) async throws -> PestySnapshot? {
        let id = recordID ?? Self.defaultSnapshotRecordID
        let database = database(for: scope)
        guard let record = try await fetchRecord(id, from: database) else {
            return nil
        }
        return try CloudKitSnapshotPayload.decode(from: record)
    }

    @discardableResult
    public func push(
        _ snapshot: PestySnapshot,
        scope: CloudDatabaseScope = .private,
        recordID: CKRecord.ID? = nil,
        historyLimit: Int = .max
    ) async throws -> CKRecord.ID {
        let id = recordID ?? Self.defaultSnapshotRecordID
        _ = try await reconcile(
            snapshot,
            scope: scope,
            recordID: id,
            historyLimit: historyLimit
        )
        return id
    }

    public func reconcile(
        _ snapshot: PestySnapshot,
        scope: CloudDatabaseScope = .private,
        recordID: CKRecord.ID? = nil,
        historyLimit: Int = .max
    ) async throws -> PestySnapshot {
        let id = recordID ?? Self.defaultSnapshotRecordID
        let database = database(for: scope)
        var candidate = snapshot

        for _ in 0..<4 {
            let existing = try await fetchRecord(id, from: database)
            if let existing {
                candidate = SnapshotMerger.merge(
                    local: candidate,
                    remote: try CloudKitSnapshotPayload.decode(from: existing),
                    historyLimit: historyLimit
                )
            }

            let record = existing
                ?? CKRecord(recordType: Self.snapshotRecordType, recordID: id)
            let payloadURL = try CloudKitSnapshotPayload.attach(
                candidate,
                to: record
            )
            setSnapshotMetadata(candidate, on: record)

            do {
                _ = try await save([record], to: database)
                try? FileManager.default.removeItem(at: payloadURL)
                return candidate
            } catch {
                try? FileManager.default.removeItem(at: payloadURL)
                guard isServerRecordChanged(error) else {
                    throw error
                }
            }
        }

        throw CloudKitSyncError.conflictRetriesExhausted(id)
    }

    public func sharePinboard(
        _ pinboard: Pinboard,
        tombstones: [Tombstone] = [],
        title: String? = nil
    ) async throws -> CKShare {
        let database = container.privateCloudDatabase
        let zoneID = Self.sharedPinboardsZoneID
        try await ensureZone(zoneID, in: database)

        let recordID = Self.sharedPinboardRecordID(for: pinboard.id)
        var candidate = PestySnapshot(
            pinboards: [pinboard],
            tombstones: tombstones
        )

        for _ in 0..<4 {
            let existingRoot = try await fetchRecord(recordID, from: database)
            if let existingRoot {
                candidate = SnapshotMerger.merge(
                    local: candidate,
                    remote: try CloudKitSnapshotPayload.decode(from: existingRoot)
                )
            }

            let rootRecord = existingRoot
                ?? CKRecord(
                    recordType: Self.snapshotRecordType,
                    recordID: recordID
                )
            let share: CKShare
            if let shareID = rootRecord.share?.recordID,
               let existingShare = try await fetchRecord(shareID, from: database)
                    as? CKShare {
                share = existingShare
            } else {
                share = CKShare(rootRecord: rootRecord)
            }

            let payloadURL = try CloudKitSnapshotPayload.attach(
                candidate,
                to: rootRecord
            )
            setSnapshotMetadata(candidate, on: rootRecord)
            share[CKShare.SystemFieldKey.title] =
                (title ?? pinboard.name) as CKRecordValue

            do {
                let saved = try await save(
                    [rootRecord, share],
                    to: database
                )
                try? FileManager.default.removeItem(at: payloadURL)
                guard let savedShare = saved.first(where: {
                    $0.recordID == share.recordID
                }) as? CKShare else {
                    throw CloudKitSyncError.missingRecordResult(share.recordID)
                }
                return savedShare
            } catch {
                try? FileManager.default.removeItem(at: payloadURL)
                guard isShareRetryable(error) else {
                    throw error
                }
            }
        }

        throw CloudKitSyncError.conflictRetriesExhausted(recordID)
    }

    public func acceptShare(_ metadata: CKShare.Metadata) async throws -> CKShare {
        let results = try await container.accept([metadata])
        guard let result = results[metadata] else {
            throw CloudKitSyncError.missingRecordResult(metadata.share.recordID)
        }
        return try result.get()
    }

    private func database(for scope: CloudDatabaseScope) -> CKDatabase {
        switch scope {
        case .private:
            container.privateCloudDatabase
        case .shared:
            container.sharedCloudDatabase
        }
    }

    private func setSnapshotMetadata(_ snapshot: PestySnapshot, on record: CKRecord) {
        record[Field.schemaVersion] = snapshot.schemaVersion as CKRecordValue
        record[Field.updatedAt] = snapshot.updatedAt as CKRecordValue
    }

    private func fetchRecord(
        _ recordID: CKRecord.ID,
        from database: CKDatabase
    ) async throws -> CKRecord? {
        let results = try await database.records(for: [recordID])
        guard let result = results[recordID] else {
            throw CloudKitSyncError.missingRecordResult(recordID)
        }

        switch result {
        case .success(let record):
            return record
        case .failure(let error as CKError) where error.code == .unknownItem:
            return nil
        case .failure(let error):
            throw error
        }
    }

    private func save(
        _ records: [CKRecord],
        to database: CKDatabase
    ) async throws -> [CKRecord] {
        let result = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )

        return try records.map { record in
            guard let saveResult = result.saveResults[record.recordID] else {
                throw CloudKitSyncError.missingRecordResult(record.recordID)
            }
            return try saveResult.get()
        }
    }

    private func isServerRecordChanged(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else {
            return false
        }
        if cloudError.code == .serverRecordChanged {
            return true
        }
        guard cloudError.code == .partialFailure,
              let partialErrors = cloudError.partialErrorsByItemID else {
            return false
        }
        return partialErrors.values.contains(where: isServerRecordChanged)
    }

    private func isShareRetryable(_ error: Error) -> Bool {
        if isServerRecordChanged(error) {
            return true
        }
        guard let cloudError = error as? CKError else {
            return false
        }
        if cloudError.code == .alreadyShared {
            return true
        }
        guard cloudError.code == .partialFailure,
              let partialErrors = cloudError.partialErrorsByItemID else {
            return false
        }
        return partialErrors.values.contains(where: isShareRetryable)
    }

    private func ensureZone(
        _ zoneID: CKRecordZone.ID,
        in database: CKDatabase
    ) async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        let result = try await database.modifyRecordZones(
            saving: [zone],
            deleting: []
        )
        guard let saveResult = result.saveResults[zoneID] else {
            throw CloudKitSyncError.missingRecordResult(
                CKRecord.ID(recordName: zoneID.zoneName, zoneID: zoneID)
            )
        }
        _ = try saveResult.get()
    }
}
