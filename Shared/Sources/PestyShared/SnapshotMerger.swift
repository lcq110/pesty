import Foundation

public enum SnapshotMerger {
    private struct MembershipKey: Hashable {
        let parentID: UUID
        let clipID: UUID
    }

    public static func merge(
        local: PestySnapshot,
        remote: PestySnapshot,
        historyLimit: Int = .max
    ) -> PestySnapshot {
        let tombstones = mergeTombstones(local.tombstones + remote.tombstones)
        let clipDeletions = tombstonesByID(tombstones, kind: .clip)
        let boardDeletions = tombstonesByID(tombstones, kind: .pinboard)
        let historyDeletions = tombstonesByID(tombstones, kind: .historyClip)
        let pinboardClipDeletions = membershipTombstones(
            tombstones,
            kind: .pinboardClip
        )

        let history = mergeItems(local.history + remote.history)
            .filter { item in
                guard let deletedAt = latest(
                    clipDeletions[item.id],
                    historyDeletions[item.id]
                ) else {
                    return true
                }
                return item.updatedAt > deletedAt
            }
            .deduplicatedByContent()
            .prefix(max(0, historyLimit))

        let pinboards = mergeBoards(
            local.pinboards + remote.pinboards,
            clipDeletions: clipDeletions,
            membershipDeletions: pinboardClipDeletions
        )
        .filter { board in
            guard let deletedAt = boardDeletions[board.id] else {
                return true
            }
            return board.updatedAt > deletedAt
        }
        let sharedPinboardReferences = mergeSharedPinboardReferences(
            local.sharedPinboardReferences + remote.sharedPinboardReferences
        ).sorted {
            if $0.ownerName != $1.ownerName {
                return $0.ownerName < $1.ownerName
            }
            if $0.zoneName != $1.zoneName {
                return $0.zoneName < $1.zoneName
            }
            return $0.recordName < $1.recordName
        }

        return PestySnapshot(
            history: Array(history),
            pinboards: pinboards,
            sharedPinboardReferences: sharedPinboardReferences,
            tombstones: tombstones,
            schemaVersion: max(local.schemaVersion, remote.schemaVersion),
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private static func mergeItems(_ items: [ClipItem]) -> [ClipItem] {
        var byID: [UUID: ClipItem] = [:]
        for item in items {
            if let existing = byID[item.id] {
                byID[item.id] = preferredItem(existing, item)
            } else {
                byID[item.id] = item
            }
        }
        return byID.values.sorted(by: itemOrder)
    }

    private static func mergeBoards(
        _ boards: [Pinboard],
        clipDeletions: [UUID: Date],
        membershipDeletions: [MembershipKey: Date]
    ) -> [Pinboard] {
        var byID: [UUID: Pinboard] = [:]

        for board in boards {
            if let existing = byID[board.id] {
                let metadata = preferredBoard(existing, board)
                let items = mergeItems(existing.items + board.items)
                    .filter { item in
                        let membershipKey = MembershipKey(
                            parentID: board.id,
                            clipID: item.id
                        )
                        guard let deletedAt = latest(
                            clipDeletions[item.id],
                            membershipDeletions[membershipKey]
                        ) else {
                            return true
                        }
                        return item.updatedAt > deletedAt
                    }
                    .deduplicatedByContent()
                byID[board.id] = Pinboard(
                    id: metadata.id,
                    name: metadata.name,
                    colorHex: metadata.colorHex,
                    items: items,
                    updatedAt: max(existing.updatedAt, board.updatedAt)
                )
            } else {
                var copy = board
                copy.items = mergeItems(copy.items)
                    .filter { item in
                        let membershipKey = MembershipKey(
                            parentID: board.id,
                            clipID: item.id
                        )
                        guard let deletedAt = latest(
                            clipDeletions[item.id],
                            membershipDeletions[membershipKey]
                        ) else {
                            return true
                        }
                        return item.updatedAt > deletedAt
                    }
                    .deduplicatedByContent()
                byID[board.id] = copy
            }
        }

        return byID.values.sorted {
            let leftName = $0.name.lowercased()
            let rightName = $1.name.lowercased()
            if leftName != rightName {
                return leftName < rightName
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func preferredItem(_ left: ClipItem, _ right: ClipItem) -> ClipItem {
        if left.updatedAt != right.updatedAt {
            return left.updatedAt > right.updatedAt ? left : right
        }
        return itemTieBreaker(left) >= itemTieBreaker(right) ? left : right
    }

    private static func preferredBoard(_ left: Pinboard, _ right: Pinboard) -> Pinboard {
        if left.updatedAt != right.updatedAt {
            return left.updatedAt > right.updatedAt ? left : right
        }
        return boardTieBreaker(left) >= boardTieBreaker(right) ? left : right
    }

    private static func itemOrder(_ left: ClipItem, _ right: ClipItem) -> Bool {
        if left.createdAt != right.createdAt {
            return left.createdAt > right.createdAt
        }
        return left.id.uuidString < right.id.uuidString
    }

    private static func itemTieBreaker(_ item: ClipItem) -> String {
        let fileURLs = item.fileURLs
            .map(stableComponent)
            .joined()
        let fields: [String] = [
            item.id.uuidString,
            item.type.rawValue,
            item.text ?? "",
            item.rtfData?.base64EncodedString() ?? "",
            item.imageFileName ?? "",
            item.imageHash ?? "",
            fileURLs,
            item.colorHex ?? "",
            item.sourceBundleID ?? "",
            item.sourceAppName ?? "",
            item.customTitle ?? "",
            String(item.createdAt.timeIntervalSinceReferenceDate.bitPattern),
        ]
        return fields.map(stableComponent).joined()
    }

    private static func boardTieBreaker(_ board: Pinboard) -> String {
        [board.name, board.colorHex]
            .map(stableComponent)
            .joined()
    }

    private static func mergeTombstones(_ tombstones: [Tombstone]) -> [Tombstone] {
        struct Key: Hashable {
            let kind: TombstoneKind
            let id: UUID
            let parentID: UUID?
        }

        var byKey: [Key: Tombstone] = [:]
        for tombstone in tombstones {
            let key = Key(
                kind: tombstone.kind,
                id: tombstone.id,
                parentID: tombstone.parentID
            )
            if let existing = byKey[key], existing.deletedAt >= tombstone.deletedAt {
                continue
            }
            byKey[key] = tombstone
        }

        return byKey.values.sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            let leftParent = $0.parentID?.uuidString ?? ""
            let rightParent = $1.parentID?.uuidString ?? ""
            if leftParent != rightParent {
                return leftParent < rightParent
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func mergeSharedPinboardReferences(
        _ references: [SharedPinboardReference]
    ) -> [SharedPinboardReference] {
        var byID: [String: SharedPinboardReference] = [:]
        for reference in references {
            guard let existing = byID[reference.id] else {
                byID[reference.id] = reference
                continue
            }
            byID[reference.id] = permissionRank(reference.permission)
                > permissionRank(existing.permission)
                ? reference
                : existing
        }
        return Array(byID.values)
    }

    private static func permissionRank(
        _ permission: SharedPinboardPermission
    ) -> Int {
        switch permission {
        case .readOnly: 0
        case .readWrite: 1
        case .owner: 2
        }
    }

    private static func tombstonesByID(
        _ tombstones: [Tombstone],
        kind: TombstoneKind
    ) -> [UUID: Date] {
        Dictionary(
            uniqueKeysWithValues: tombstones
                .filter { $0.kind == kind }
                .map { ($0.id, $0.deletedAt) }
        )
    }

    private static func membershipTombstones(
        _ tombstones: [Tombstone],
        kind: TombstoneKind
    ) -> [MembershipKey: Date] {
        Dictionary(
            uniqueKeysWithValues: tombstones.compactMap { tombstone in
                guard tombstone.kind == kind,
                      let parentID = tombstone.parentID else {
                    return nil
                }
                return (
                    MembershipKey(parentID: parentID, clipID: tombstone.id),
                    tombstone.deletedAt
                )
            }
        )
    }

    private static func latest(_ left: Date?, _ right: Date?) -> Date? {
        switch (left, right) {
        case (.some(let left), .some(let right)):
            return max(left, right)
        case (.some(let left), .none):
            return left
        case (.none, .some(let right)):
            return right
        case (.none, .none):
            return nil
        }
    }
}

private extension Array where Element == ClipItem {
    func deduplicatedByContent() -> [ClipItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.contentIdentity).inserted }
    }
}

private extension ClipItem {
    var contentIdentity: String {
        switch type {
        case .image:
            return "img:" + (imageHash ?? imageFileName ?? id.uuidString)
        case .color:
            return "col:" + (colorHex ?? "")
        case .file:
            return "file:" + fileURLs.map(stableComponent).joined()
        case .text:
            return "txt:" + stableComponent(text ?? "")
        case .richText:
            return "rtf:" + [
                text ?? "",
                rtfData?.base64EncodedString() ?? "",
            ].map(stableComponent).joined()
        case .link:
            return "link:" + stableComponent(text ?? "")
        }
    }
}

private func stableComponent(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
}
