import Foundation
import Testing
@testable import PestyShared

@Suite
struct LegacyCodableTests {
    @Test
    func testDecodesExistingStoreJSONWithoutSyncMetadata() throws {
        let json = """
        {
          "history": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "type": "richText",
              "text": "Legacy clip",
              "rtfData": "SGVsbG8=",
              "fileURLs": [],
              "createdAt": 1234
            }
          ],
          "pinboards": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Legacy board",
              "colorHex": "#B663E0",
              "items": []
            }
          ]
        }
        """

        let snapshot = try JSONDecoder().decode(
            PestySnapshot.self,
            from: Data(json.utf8)
        )

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.tombstones.isEmpty)
        #expect(snapshot.sharedPinboardReferences.isEmpty)
        #expect(snapshot.history.first?.type == .richText)
        #expect(snapshot.history.first?.fileURLs == [])
        #expect(snapshot.history.first?.updatedAt == snapshot.history.first?.createdAt)
        #expect(snapshot.pinboards.first?.name == "Legacy board")
        #expect(snapshot.pinboards.first?.updatedAt == .distantPast)
    }

    @Test
    func testNewSnapshotStillDecodesWithLegacyShape() throws {
        let date = Date(timeIntervalSinceReferenceDate: 42)
        let item = ClipItem(type: .text, text: "Compatible", createdAt: date)
        let snapshot = PestySnapshot(
            history: [item],
            pinboards: [Pinboard(name: "Favorites", updatedAt: date)]
        )

        let data = try JSONEncoder().encode(snapshot)
        let legacy = try JSONDecoder().decode(LegacySnapshot.self, from: data)

        #expect(legacy.history.map(\.text) == ["Compatible"])
        #expect(legacy.pinboards.map(\.name) == ["Favorites"])
    }

    @Test
    func testLegacyTombstoneDecodesWithoutParentID() throws {
        let json = """
        {
          "kind": "clip",
          "id": "33333333-3333-3333-3333-333333333333",
          "deletedAt": 42
        }
        """

        let tombstone = try JSONDecoder().decode(
            Tombstone.self,
            from: Data(json.utf8)
        )

        #expect(tombstone.kind == .clip)
        #expect(tombstone.parentID == nil)
    }

    @Test
    func testLegacySharedReferenceDefaultsToReadOnly() throws {
        let data = Data(
            """
            {
              "recordName": "board",
              "zoneName": "shared-zone",
              "ownerName": "owner"
            }
            """.utf8
        )

        let reference = try JSONDecoder().decode(
            SharedPinboardReference.self,
            from: data
        )

        #expect(reference.permission == .readOnly)
    }
}

private struct LegacySnapshot: Codable {
    let history: [LegacyClipItem]
    let pinboards: [LegacyPinboard]
}

private struct LegacyClipItem: Codable {
    let id: UUID
    let type: ClipType
    let text: String?
    let rtfData: Data?
    let imageFileName: String?
    let imageHash: String?
    let fileURLs: [String]
    let colorHex: String?
    let sourceBundleID: String?
    let sourceAppName: String?
    let customTitle: String?
    let createdAt: Date
}

private struct LegacyPinboard: Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let items: [LegacyClipItem]
}
