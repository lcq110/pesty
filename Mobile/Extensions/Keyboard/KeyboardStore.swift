import Combine
import Foundation

enum KeyboardSharedPaths {
    static let appGroupIdentifier = "group.com.greycorelabs.pesty"

    static var container: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )!
    }

    static var store: URL {
        container.appendingPathComponent("store.json")
    }

    static var images: URL {
        container.appendingPathComponent("images", isDirectory: true)
    }

    static var files: URL {
        container.appendingPathComponent("files", isDirectory: true)
    }
}

extension KeyboardClip {
    var resolvedFileURLs: [URL] {
        fileURLs.enumerated().compactMap { index, value in
            let original: URL
            if let url = URL(string: value), url.scheme != nil {
                original = url
            } else {
                original = URL(fileURLWithPath: value)
            }
            if FileManager.default.fileExists(atPath: original.path) {
                return original
            }

            let name = original.lastPathComponent.isEmpty
                ? "File"
                : original.lastPathComponent
            let cached = KeyboardSharedPaths.files.appendingPathComponent(
                "\(id.uuidString)-\(index)-\(name)"
            )
            return FileManager.default.fileExists(atPath: cached.path)
                ? cached
                : nil
        }
    }
}

struct KeyboardClip: Decodable, Identifiable, Equatable {
    let id: UUID
    let type: String
    let text: String?
    let rtfData: Data?
    let imageFileName: String?
    let fileURLs: [String]
    let colorHex: String?
    let sourceAppName: String?
    let customTitle: String?
    let createdAt: Date

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }

        switch type {
        case "link":
            let value = text ?? "Link"
            return URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))?.host
                ?? value
        case "image":
            return imageFileName ?? "Image"
        case "file":
            guard let first = fileURLs.first else { return "File" }
            return URL(string: first)?.lastPathComponent
                ?? URL(fileURLWithPath: first).lastPathComponent
        case "color":
            return colorHex ?? "Color"
        default:
            let firstLine = (text ?? "")
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
                ?? ""
            return firstLine.isEmpty ? typeLabel : String(firstLine.prefix(100))
        }
    }

    var typeLabel: String {
        switch type {
        case "richText": return "Rich Text"
        default: return type.capitalized
        }
    }

    var symbolName: String {
        switch type {
        case "text": return "text.alignleft"
        case "richText": return "doc.richtext"
        case "link": return "link"
        case "image": return "photo"
        case "file": return "doc"
        case "color": return "paintpalette"
        default: return "square.on.square"
        }
    }

    var searchableText: String {
        [
            customTitle,
            text,
            sourceAppName,
            fileURLs.joined(separator: " "),
            colorHex
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}

struct KeyboardPinboard: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let colorHex: String
    let items: [KeyboardClip]
}

private struct KeyboardSnapshot: Decodable {
    let history: [KeyboardClip]
    let pinboards: [KeyboardPinboard]
}

enum KeyboardSource: Hashable, Identifiable {
    case history
    case pinboard(UUID)

    var id: String {
        switch self {
        case .history: return "history"
        case .pinboard(let id): return id.uuidString
        }
    }
}

@MainActor
final class KeyboardStore: ObservableObject {
    @Published private(set) var history: [KeyboardClip] = []
    @Published private(set) var pinboards: [KeyboardPinboard] = []
    @Published var source: KeyboardSource = .history
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?

    init() {
        reload()
    }

    var visibleItems: [KeyboardClip] {
        let items: [KeyboardClip]
        switch source {
        case .history:
            items = history
        case .pinboard(let id):
            items = pinboards.first(where: { $0.id == id })?.items ?? []
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return query.isEmpty
            ? items
            : items.filter { $0.searchableText.contains(query) }
    }

    func reload() {
        guard FileManager.default.fileExists(atPath: KeyboardSharedPaths.store.path) else {
            history = []
            pinboards = []
            errorMessage = "Open Pesty once to sync your clips."
            return
        }

        do {
            let data = try Data(contentsOf: KeyboardSharedPaths.store)
            let snapshot = try JSONDecoder().decode(KeyboardSnapshot.self, from: data)
            history = snapshot.history
            pinboards = snapshot.pinboards
            errorMessage = nil

            if case .pinboard(let selectedID) = source,
               !pinboards.contains(where: { $0.id == selectedID }) {
                source = .history
            }
        } catch {
            history = []
            pinboards = []
            errorMessage = error.localizedDescription
        }
    }
}
