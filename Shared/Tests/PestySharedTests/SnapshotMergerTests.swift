import Foundation
import Testing
@testable import PestyShared

@Suite
struct SnapshotMergerTests {
    @Test
    func testMergeIsCommutativeAndUsesLatestUpdate() {
        let itemID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let boardID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let oldItem = item(
            id: itemID,
            text: "Old",
            created: 1,
            updated: 2
        )
        let newItem = item(
            id: itemID,
            text: "New",
            created: 1,
            updated: 4
        )
        let local = PestySnapshot(
            history: [oldItem],
            pinboards: [
                Pinboard(
                    id: boardID,
                    name: "Old name",
                    items: [oldItem],
                    updatedAt: date(2)
                )
            ]
        )
        let remote = PestySnapshot(
            history: [newItem],
            pinboards: [
                Pinboard(
                    id: boardID,
                    name: "New name",
                    items: [newItem],
                    updatedAt: date(4)
                )
            ]
        )

        let localFirst = SnapshotMerger.merge(local: local, remote: remote)
        let remoteFirst = SnapshotMerger.merge(local: remote, remote: local)

        #expect(localFirst == remoteFirst)
        #expect(localFirst.history.map(\.text) == ["New"])
        #expect(localFirst.pinboards.first?.name == "New name")
        #expect(localFirst.pinboards.first?.items.map(\.text) == ["New"])
    }

    @Test
    func testEqualTimestampsUseStableTieBreakerAndOrdering() {
        let itemID = UUID(uuidString: "01000000-0000-0000-0000-000000000000")!
        let sameDate = date(5)
        let local = PestySnapshot(
            history: [
                ClipItem(
                    id: itemID,
                    type: .text,
                    text: "Alpha",
                    createdAt: sameDate,
                    updatedAt: sameDate
                )
            ],
            pinboards: [
                Pinboard(
                    id: UUID(uuidString: "02000000-0000-0000-0000-000000000000")!,
                    name: "Zulu",
                    updatedAt: sameDate
                )
            ]
        )
        let remote = PestySnapshot(
            history: [
                ClipItem(
                    id: itemID,
                    type: .text,
                    text: "Zulu",
                    createdAt: sameDate,
                    updatedAt: sameDate
                )
            ],
            pinboards: [
                Pinboard(
                    id: UUID(uuidString: "03000000-0000-0000-0000-000000000000")!,
                    name: "Alpha",
                    updatedAt: sameDate
                )
            ]
        )

        let localFirst = SnapshotMerger.merge(local: local, remote: remote)
        let remoteFirst = SnapshotMerger.merge(local: remote, remote: local)

        #expect(localFirst == remoteFirst)
        #expect(localFirst.history.count == 1)
        #expect(localFirst.pinboards.map(\.name) == ["Alpha", "Zulu"])
    }

    @Test
    func testTombstoneDeletesClipFromHistoryAndPinboards() {
        let clipID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let boardID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let clip = item(id: clipID, text: "Delete me", created: 1, updated: 2)
        let local = PestySnapshot(
            history: [clip],
            pinboards: [
                Pinboard(
                    id: boardID,
                    name: "Board",
                    items: [clip],
                    updatedAt: date(2)
                )
            ]
        )
        let remote = PestySnapshot(
            tombstones: [
                Tombstone(kind: .clip, id: clipID, deletedAt: date(3))
            ]
        )

        let merged = SnapshotMerger.merge(local: local, remote: remote)

        #expect(merged.history.isEmpty)
        #expect(merged.pinboards[0].items.isEmpty)
        #expect(merged.tombstones.count == 1)
    }

    @Test
    func testGlobalDeleteCreatesScopedPinboardMembershipTombstone() {
        let clipID = UUID(
            uuidString: "CCCCCCCC-1111-2222-3333-CCCCCCCCCCCC"
        )!
        let boardID = UUID(
            uuidString: "DDDDDDDD-1111-2222-3333-DDDDDDDDDDDD"
        )!
        let clip = item(
            id: clipID,
            text: "Shared",
            created: 1,
            updated: 1
        )
        var snapshot = PestySnapshot(
            history: [clip],
            pinboards: [
                Pinboard(
                    id: boardID,
                    name: "Board",
                    items: [clip],
                    updatedAt: date(1)
                )
            ]
        )

        snapshot.deleteClip(id: clipID, at: date(2))
        let scoped = snapshot.scoped(toPinboard: boardID)

        #expect(scoped.pinboards.count == 1)
        #expect(scoped.pinboards[0].items.isEmpty)
        #expect(scoped.tombstones == [
            Tombstone(
                kind: .pinboardClip,
                id: clipID,
                parentID: boardID,
                deletedAt: date(2)
            )
        ])
    }

    @Test
    func testUpdateAfterTombstoneResurrectsClip() {
        let clipID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let local = PestySnapshot(
            tombstones: [
                Tombstone(kind: .clip, id: clipID, deletedAt: date(3))
            ]
        )
        let remote = PestySnapshot(
            history: [
                item(id: clipID, text: "Restored", created: 1, updated: 4)
            ]
        )

        let merged = SnapshotMerger.merge(local: local, remote: remote)

        #expect(merged.history.map(\.text) == ["Restored"])
    }

    @Test
    func testClearHistoryDoesNotDeletePinnedCopy() {
        let clipID = UUID(uuidString: "11111111-AAAA-BBBB-CCCC-111111111111")!
        let boardID = UUID(uuidString: "22222222-AAAA-BBBB-CCCC-222222222222")!
        let clip = item(id: clipID, text: "Pinned", created: 1, updated: 1)
        var local = PestySnapshot(
            history: [clip],
            pinboards: [
                Pinboard(
                    id: boardID,
                    name: "Pinned",
                    items: [clip],
                    updatedAt: date(1)
                )
            ]
        )
        local.clearHistory(at: date(2))
        let staleRemote = PestySnapshot(history: [clip])

        let merged = SnapshotMerger.merge(local: local, remote: staleRemote)

        #expect(merged.history.isEmpty)
        #expect(merged.pinboards.first?.items.map(\.id) == [clipID])
    }

    @Test
    func testPinboardMembershipDeletionAndLaterReAdd() {
        let clipID = UUID(uuidString: "33333333-AAAA-BBBB-CCCC-333333333333")!
        let boardID = UUID(uuidString: "44444444-AAAA-BBBB-CCCC-444444444444")!
        let oldClip = item(id: clipID, text: "Member", created: 1, updated: 1)
        let board = Pinboard(
            id: boardID,
            name: "Board",
            items: [oldClip],
            updatedAt: date(1)
        )
        var removed = PestySnapshot(
            history: [oldClip],
            pinboards: [board]
        )
        removed.removeClip(id: clipID, fromPinboard: boardID, at: date(2))

        let afterRemoval = SnapshotMerger.merge(
            local: removed,
            remote: PestySnapshot(history: [oldClip], pinboards: [board])
        )
        #expect(afterRemoval.history.map(\.id) == [clipID])
        #expect(afterRemoval.pinboards.first?.items.isEmpty == true)

        let addedAgain = item(
            id: clipID,
            text: "Member",
            created: 1,
            updated: 3
        )
        let reAdded = PestySnapshot(
            history: [oldClip],
            pinboards: [
                Pinboard(
                    id: boardID,
                    name: "Board",
                    items: [addedAgain],
                    updatedAt: date(3)
                )
            ]
        )
        let afterReAdd = SnapshotMerger.merge(
            local: removed,
            remote: reAdded
        )

        #expect(afterReAdd.pinboards.first?.items.map(\.id) == [clipID])
    }

    @Test
    func testBoardTombstoneAndHistoryLimit() {
        let deletedID = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
        let survivorID = UUID(uuidString: "20000000-0000-0000-0000-000000000000")!
        let local = PestySnapshot(
            history: [
                item(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000000")!,
                    text: "Third",
                    created: 3,
                    updated: 3
                ),
                item(
                    id: UUID(uuidString: "40000000-0000-0000-0000-000000000000")!,
                    text: "Second",
                    created: 2,
                    updated: 2
                ),
                item(
                    id: UUID(uuidString: "50000000-0000-0000-0000-000000000000")!,
                    text: "First",
                    created: 1,
                    updated: 1
                ),
            ],
            pinboards: [
                Pinboard(id: deletedID, name: "Deleted", updatedAt: date(1)),
                Pinboard(id: survivorID, name: "Survivor", updatedAt: date(4)),
            ]
        )
        let remote = PestySnapshot(
            tombstones: [
                Tombstone(kind: .pinboard, id: deletedID, deletedAt: date(2))
            ]
        )

        let merged = SnapshotMerger.merge(
            local: local,
            remote: remote,
            historyLimit: 2
        )

        #expect(merged.history.map(\.text) == ["Third", "Second"])
        #expect(merged.pinboards.map(\.id) == [survivorID])
    }

    @Test
    func testMergePersistsSharedPinboardReferences() {
        let first = SharedPinboardReference(
            recordName: "first",
            zoneName: "Shared",
            ownerName: "owner-a"
        )
        let second = SharedPinboardReference(
            recordName: "second",
            zoneName: "Shared",
            ownerName: "owner-b"
        )
        let local = PestySnapshot(sharedPinboardReferences: [second])
        let remote = PestySnapshot(sharedPinboardReferences: [first, second])

        let merged = SnapshotMerger.merge(local: local, remote: remote)

        #expect(merged.sharedPinboardReferences == [first, second])
        #expect(
            merged == SnapshotMerger.merge(local: remote, remote: local)
        )
    }

    @Test
    func testMergeKeepsOneSharedReferenceWithWritablePermission() {
        let readOnly = SharedPinboardReference(
            recordName: "board",
            zoneName: "Shared",
            ownerName: "owner",
            permission: .readOnly
        )
        let readWrite = SharedPinboardReference(
            recordName: "board",
            zoneName: "Shared",
            ownerName: "owner",
            permission: .readWrite
        )

        let merged = SnapshotMerger.merge(
            local: PestySnapshot(sharedPinboardReferences: [readOnly]),
            remote: PestySnapshot(sharedPinboardReferences: [readWrite])
        )

        #expect(merged.sharedPinboardReferences == [readWrite])
        #expect(
            merged == SnapshotMerger.merge(
                local: PestySnapshot(
                    sharedPinboardReferences: [readWrite]
                ),
                remote: PestySnapshot(
                    sharedPinboardReferences: [readOnly]
                )
            )
        )
    }

    @Test
    func testContentDeduplicationPreservesTypeAndRichTextPayload() {
        let plain = ClipItem(
            id: UUID(uuidString: "60000000-0000-0000-0000-000000000000")!,
            type: .text,
            text: "pesty.dev",
            createdAt: date(4)
        )
        let link = ClipItem(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000000")!,
            type: .link,
            text: "pesty.dev",
            createdAt: date(3)
        )
        let firstRichText = ClipItem(
            id: UUID(uuidString: "80000000-0000-0000-0000-000000000000")!,
            type: .richText,
            text: "pesty.dev",
            rtfData: Data("first".utf8),
            createdAt: date(2)
        )
        let secondRichText = ClipItem(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000000")!,
            type: .richText,
            text: "pesty.dev",
            rtfData: Data("second".utf8),
            createdAt: date(1)
        )

        let merged = SnapshotMerger.merge(
            local: PestySnapshot(
                history: [plain, link, firstRichText, secondRichText]
            ),
            remote: PestySnapshot()
        )

        #expect(merged.history.map(\.id) == [
            plain.id,
            link.id,
            firstRichText.id,
            secondRichText.id,
        ])
        #expect(!plain.sameContent(as: link))
        #expect(!firstRichText.sameContent(as: secondRichText))
    }

    private func item(
        id: UUID,
        text: String,
        created: TimeInterval,
        updated: TimeInterval
    ) -> ClipItem {
        ClipItem(
            id: id,
            type: .text,
            text: text,
            createdAt: date(created),
            updatedAt: date(updated)
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }
}
