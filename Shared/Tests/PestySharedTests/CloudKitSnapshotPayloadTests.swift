import CloudKit
import Foundation
import Testing
@testable import PestyShared

@Suite
struct CloudKitSnapshotPayloadTests {
    @Test
    func testAssetPayloadRoundTrip() throws {
        let snapshot = sampleSnapshot()
        let record = CKRecord(
            recordType: CloudKitSyncService.snapshotRecordType
        )

        let payloadURL = try CloudKitSnapshotPayload.attach(
            snapshot,
            to: record
        )
        defer {
            try? FileManager.default.removeItem(at: payloadURL)
        }

        #expect(record[CloudKitSnapshotPayload.assetField] is CKAsset)
        #expect(record[CloudKitSnapshotPayload.legacyDataField] == nil)
        #expect(try CloudKitSnapshotPayload.decode(from: record) == snapshot)
    }

    @Test
    func testLegacyDataPayloadStillDecodes() throws {
        let snapshot = sampleSnapshot()
        let record = CKRecord(
            recordType: CloudKitSyncService.snapshotRecordType
        )
        record[CloudKitSnapshotPayload.legacyDataField] =
            try SnapshotCoding.encoder.encode(snapshot) as CKRecordValue

        #expect(try CloudKitSnapshotPayload.decode(from: record) == snapshot)
    }

    private func sampleSnapshot() -> PestySnapshot {
        let date = Date(timeIntervalSinceReferenceDate: 42)
        return PestySnapshot(
            history: [
                ClipItem(
                    type: .richText,
                    text: "CloudKit payload",
                    rtfData: Data("{\\rtf1 CloudKit payload}".utf8),
                    htmlData: Data("<strong>CloudKit payload</strong>".utf8),
                    createdAt: date
                )
            ],
            updatedAt: date
        )
    }
}
