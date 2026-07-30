import Foundation
import Testing
@testable import PestyShared

@Suite
struct SharedSnapshotStoreTests {
    @Test
    func testSaveAndLoadRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PestySharedTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SharedSnapshotStore(directoryURL: directory)
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let snapshot = PestySnapshot(
            history: [
                ClipItem(type: .link, text: "https://example.com", createdAt: date)
            ],
            pinboards: [
                Pinboard(name: "Links", updatedAt: date)
            ]
        )

        #expect(try store.load() == nil)
        try store.save(snapshot)

        #expect(store.snapshotURL.lastPathComponent == "store.json")
        #expect(try store.load() == snapshot)

        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: store.snapshotURL)
        ) as? [String: Any]
        #expect(json?["history"] != nil)
        #expect(json?["pinboards"] != nil)
    }
}
