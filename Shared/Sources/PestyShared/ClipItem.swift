import Foundation

public struct ClipItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var type: ClipType
    public var text: String?
    public var rtfData: Data?
    public var imageFileName: String?
    public var imageHash: String?
    public var fileURLs: [String]
    public var colorHex: String?
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var customTitle: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: ClipType,
        text: String? = nil,
        rtfData: Data? = nil,
        imageFileName: String? = nil,
        imageHash: String? = nil,
        fileURLs: [String] = [],
        colorHex: String? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        customTitle: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.rtfData = rtfData
        self.imageFileName = imageFileName
        self.imageHash = imageHash
        self.fileURLs = fileURLs
        self.colorHex = colorHex
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.customTitle = customTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var charCount: Int {
        text?.count ?? 0
    }

    public var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }

        switch type {
        case .link:
            let value = text ?? ""
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: trimmed)?.host ?? (value.isEmpty ? "Link" : value)
        case .image:
            return "Image"
        case .file:
            return fileURLs.first
                .flatMap(URL.init(string:))?
                .lastPathComponent ?? "File"
        case .color:
            return colorHex ?? "Color"
        case .text, .richText:
            let firstLine = (text ?? "")
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? ""
            return firstLine.isEmpty ? type.label : String(firstLine.prefix(60))
        }
    }

    public var searchableText: String {
        [customTitle, text, sourceAppName, fileURLs.joined(separator: " "), colorHex]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    public func sameContent(as other: ClipItem) -> Bool {
        guard type == other.type else {
            return false
        }

        switch type {
        case .image:
            if let imageHash, let otherHash = other.imageHash {
                return imageHash == otherHash
            }
            return imageFileName == other.imageFileName
        case .color:
            return colorHex == other.colorHex
        case .file:
            return fileURLs == other.fileURLs
        case .text, .link:
            return text == other.text
        case .richText:
            return text == other.text && rtfData == other.rtfData
        }
    }
}

extension ClipItem {
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case text
        case rtfData
        case imageFileName
        case imageHash
        case fileURLs
        case colorHex
        case sourceBundleID
        case sourceAppName
        case customTitle
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ClipType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        fileURLs = try container.decodeIfPresent([String].self, forKey: .fileURLs) ?? []
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}
