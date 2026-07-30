import Foundation

public enum TombstoneKind: String, Codable, CaseIterable, Sendable {
    case clip
    case pinboard
    case historyClip
    case pinboardClip
}

public struct Tombstone: Codable, Equatable, Hashable, Sendable {
    public let kind: TombstoneKind
    public let id: UUID
    public let parentID: UUID?
    public var deletedAt: Date

    public init(
        kind: TombstoneKind,
        id: UUID,
        parentID: UUID? = nil,
        deletedAt: Date = Date()
    ) {
        self.kind = kind
        self.id = id
        self.parentID = parentID
        self.deletedAt = deletedAt
    }
}

public enum SharedPinboardPermission: String, Codable, Sendable {
    case owner
    case readOnly
    case readWrite
}

public struct SharedPinboardReference: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var recordName: String
    public var zoneName: String
    public var ownerName: String
    public var permission: SharedPinboardPermission

    public var id: String {
        [ownerName, zoneName, recordName].joined(separator: "/")
    }

    public init(
        recordName: String,
        zoneName: String,
        ownerName: String,
        permission: SharedPinboardPermission = .readOnly
    ) {
        self.recordName = recordName
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.permission = permission
    }

    private enum CodingKeys: String, CodingKey {
        case recordName
        case zoneName
        case ownerName
        case permission
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordName = try container.decode(String.self, forKey: .recordName)
        zoneName = try container.decode(String.self, forKey: .zoneName)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        permission = try container.decodeIfPresent(
            SharedPinboardPermission.self,
            forKey: .permission
        ) ?? .readOnly
    }
}

public struct PestySnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public var history: [ClipItem]
    public var pinboards: [Pinboard]
    public var sharedPinboardReferences: [SharedPinboardReference]
    public var tombstones: [Tombstone]
    public var schemaVersion: Int
    public var updatedAt: Date

    public init(
        history: [ClipItem] = [],
        pinboards: [Pinboard] = [],
        sharedPinboardReferences: [SharedPinboardReference] = [],
        tombstones: [Tombstone] = [],
        schemaVersion: Int = PestySnapshot.currentSchemaVersion,
        updatedAt: Date? = nil
    ) {
        self.history = history
        self.pinboards = pinboards
        self.sharedPinboardReferences = sharedPinboardReferences
        self.tombstones = tombstones
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt ?? Self.latestChange(
            history: history,
            pinboards: pinboards,
            tombstones: tombstones
        )
    }

    public mutating func deleteClip(id: UUID, at date: Date = Date()) {
        let parentIDs = pinboards
            .filter { $0.items.contains(where: { $0.id == id }) }
            .map(\.id)
        history.removeAll { $0.id == id }
        for index in pinboards.indices {
            pinboards[index].items.removeAll { $0.id == id }
        }
        insert(Tombstone(kind: .clip, id: id, deletedAt: date))
        for parentID in parentIDs {
            insert(
                Tombstone(
                    kind: .pinboardClip,
                    id: id,
                    parentID: parentID,
                    deletedAt: date
                )
            )
        }
        updatedAt = max(updatedAt, date)
    }

    public mutating func deletePinboard(id: UUID, at date: Date = Date()) {
        pinboards.removeAll { $0.id == id }
        insert(Tombstone(kind: .pinboard, id: id, deletedAt: date))
        updatedAt = max(updatedAt, date)
    }

    public mutating func removeClipFromHistory(
        id: UUID,
        at date: Date = Date()
    ) {
        history.removeAll { $0.id == id }
        insert(Tombstone(kind: .historyClip, id: id, deletedAt: date))
        updatedAt = max(updatedAt, date)
    }

    public mutating func clearHistory(at date: Date = Date()) {
        let ids = Set(history.map(\.id))
        history.removeAll()
        for id in ids {
            insert(Tombstone(kind: .historyClip, id: id, deletedAt: date))
        }
        updatedAt = max(updatedAt, date)
    }

    public mutating func removeClip(
        id: UUID,
        fromPinboard pinboardID: UUID,
        at date: Date = Date()
    ) {
        guard let index = pinboards.firstIndex(where: { $0.id == pinboardID }) else {
            return
        }
        pinboards[index].items.removeAll { $0.id == id }
        insert(
            Tombstone(
                kind: .pinboardClip,
                id: id,
                parentID: pinboardID,
                deletedAt: date
            )
        )
        updatedAt = max(updatedAt, date)
    }

    private mutating func insert(_ tombstone: Tombstone) {
        if let index = tombstones.firstIndex(where: {
            $0.kind == tombstone.kind
                && $0.id == tombstone.id
                && $0.parentID == tombstone.parentID
        }) {
            tombstones[index].deletedAt = max(tombstones[index].deletedAt, tombstone.deletedAt)
        } else {
            tombstones.append(tombstone)
        }
    }

    private static func latestChange(
        history: [ClipItem],
        pinboards: [Pinboard],
        tombstones: [Tombstone]
    ) -> Date {
        let itemDate = history.map(\.updatedAt).max() ?? .distantPast
        let boardDate = pinboards.map(\.updatedAt).max() ?? .distantPast
        let deletionDate = tombstones.map(\.deletedAt).max() ?? .distantPast
        return max(itemDate, boardDate, deletionDate)
    }
}

public extension PestySnapshot {
    func scoped(toPinboard id: UUID) -> PestySnapshot {
        PestySnapshot(
            pinboards: pinboards.filter { $0.id == id },
            tombstones: tombstones.filter { tombstone in
                switch tombstone.kind {
                case .pinboard:
                    tombstone.id == id
                case .pinboardClip:
                    tombstone.parentID == id
                case .clip, .historyClip:
                    false
                }
            }
        )
    }
}

public typealias Snapshot = PestySnapshot

extension PestySnapshot {
    private enum CodingKeys: String, CodingKey {
        case history
        case pinboards
        case sharedPinboardReferences
        case tombstones
        case schemaVersion
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        history = try container.decodeIfPresent([ClipItem].self, forKey: .history) ?? []
        pinboards = try container.decodeIfPresent([Pinboard].self, forKey: .pinboards) ?? []
        sharedPinboardReferences = try container.decodeIfPresent(
            [SharedPinboardReference].self,
            forKey: .sharedPinboardReferences
        ) ?? []
        tombstones = try container.decodeIfPresent([Tombstone].self, forKey: .tombstones) ?? []
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? Self.latestChange(
                history: history,
                pinboards: pinboards,
                tombstones: tombstones
            )
    }
}
