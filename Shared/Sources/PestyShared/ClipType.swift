import Foundation

public enum ClipType: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case link
    case image
    case file
    case color

    public var label: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        case .color: "Color"
        }
    }
}
