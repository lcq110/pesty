import Foundation

public struct Pinboard: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var items: [ClipItem]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#5B8DEF",
        items: [ClipItem] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.items = items
        self.updatedAt = updatedAt
    }
}

extension Pinboard {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case items
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#5B8DEF"
        items = try container.decodeIfPresent([ClipItem].self, forKey: .items) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? items.map(\.updatedAt).max()
            ?? .distantPast
    }
}
