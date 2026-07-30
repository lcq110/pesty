import CloudKit
import Foundation
import PestyShared

struct PestyCloudKitBridge: Sendable {
    static let containerIdentifier = "iCloud.com.greycorelabs.pesty"

    private let service = CloudKitSyncService(
        containerIdentifier: containerIdentifier
    )
    private let assetService = CloudKitAssetSyncService(
        containerIdentifier: containerIdentifier
    )

    func reconcile(
        local: PestySnapshot,
        imagesDirectory: URL,
        filesDirectory: URL
    ) async throws -> PestySnapshot {
        var merged = try await service.reconcile(
            local,
            scope: .private,
            recordID: CloudKitSyncService.defaultSnapshotRecordID,
            historyLimit: .max
        )

        for reference in merged.sharedPinboardReferences {
            guard let boardID = UUID(uuidString: reference.recordName) else {
                continue
            }
            let scope: CloudDatabaseScope =
                reference.ownerName == CKCurrentUserDefaultName
                    ? .private
                    : .shared
            let sharedSnapshot: PestySnapshot
            if scope == .private || reference.permission == .readWrite {
                sharedSnapshot = try await service.reconcile(
                    merged.scoped(toPinboard: boardID),
                    scope: scope,
                    recordID: reference.recordID
                )
            } else {
                guard let pulled = try await service.pull(
                    scope: scope,
                    recordID: reference.recordID
                ) else {
                    continue
                }
                sharedSnapshot = pulled
            }

            merged = SnapshotMerger.merge(
                local: merged,
                remote: sharedSnapshot
            )
            _ = try await assetService.sync(
                snapshot: sharedSnapshot,
                scope: scope,
                zoneID: reference.recordID.zoneID,
                parentRecordID: reference.recordID,
                imagesDirectory: imagesDirectory,
                filesDirectory: filesDirectory
            )
        }

        merged = try await service.reconcile(
            merged,
            scope: .private,
            recordID: CloudKitSyncService.defaultSnapshotRecordID,
            historyLimit: .max
        )
        _ = try await assetService.sync(
            snapshot: merged,
            imagesDirectory: imagesDirectory,
            filesDirectory: filesDirectory
        )
        return merged
    }
}
