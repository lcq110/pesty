import Combine
import Foundation
import UniformTypeIdentifiers

enum ShareSharedPaths {
    static let appGroupIdentifier = "group.com.greycorelabs.pesty"

    static var container: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )!
    }

    static var store: URL {
        container.appendingPathComponent("store.json")
    }

    static var outboxDirectory: URL {
        container.appendingPathComponent("share-outbox", isDirectory: true)
    }

    static var payloadDirectory: URL {
        outboxDirectory.appendingPathComponent("payloads", isDirectory: true)
    }
}

struct SharePinboard: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
}

private struct ShareSnapshot: Decodable {
    let pinboards: [SharePinboard]
}

struct ShareDraft: Identifiable {
    let id = UUID()
    let type: String
    let text: String?
    let data: Data?
    let fileName: String?

    var displayTitle: String {
        switch type {
        case "text":
            let firstLine = (text ?? "")
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
                ?? ""
            return firstLine.isEmpty ? "Text" : String(firstLine.prefix(100))
        case "link":
            guard let text else { return "Link" }
            return URL(string: text)?.host ?? text
        case "image":
            return fileName ?? "Image"
        case "file":
            return fileName ?? "File"
        default:
            return "Clip"
        }
    }

    var subtitle: String {
        switch type {
        case "text":
            return "\(text?.count ?? 0) characters"
        case "link":
            return text ?? ""
        case "image", "file":
            return ByteCountFormatter.string(
                fromByteCount: Int64(data?.count ?? 0),
                countStyle: .file
            )
        default:
            return ""
        }
    }

    var symbolName: String {
        switch type {
        case "text": return "text.alignleft"
        case "link": return "link"
        case "image": return "photo"
        case "file": return "doc"
        default: return "square.on.square"
        }
    }
}

struct ShareOutboxEntry: Codable {
    let id: UUID
    let type: String
    let text: String?
    let payloadFileName: String?
    let fileName: String?
    let createdAt: Date
    let pinboardID: UUID?
}

enum ShareLoadError: LocalizedError {
    case unsupportedItem
    case emptyItem

    var errorDescription: String? {
        switch self {
        case .unsupportedItem:
            return "This item type is not supported by Pesty."
        case .emptyItem:
            return "The shared item contains no readable data."
        }
    }
}

enum SharePayloadLoader {
    static func load(from provider: NSItemProvider) async throws -> ShareDraft {
        if let imageType = firstRegisteredType(in: provider, conformingTo: .image) {
            return try await loadImage(from: provider, typeIdentifier: imageType)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return try await loadFileURL(from: provider)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return try await loadURL(from: provider)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return try await loadText(from: provider)
        }

        if let fileType = firstRegisteredFileType(in: provider) {
            return try await loadFile(
                from: provider,
                typeIdentifier: fileType
            )
        }

        throw ShareLoadError.unsupportedItem
    }

    private static func loadText(from provider: NSItemProvider) async throws -> ShareDraft {
        let item = try await loadItem(
            from: provider,
            typeIdentifier: UTType.plainText.identifier
        )

        let text: String
        if let value = item as? String {
            text = value
        } else if let value = item as? NSAttributedString {
            text = value.string
        } else if let value = item as? Data {
            text = String(decoding: value, as: UTF8.self)
        } else {
            throw ShareLoadError.emptyItem
        }

        return ShareDraft(type: "text", text: text, data: nil, fileName: nil)
    }

    private static func loadURL(from provider: NSItemProvider) async throws -> ShareDraft {
        let item = try await loadItem(
            from: provider,
            typeIdentifier: UTType.url.identifier
        )

        let text: String
        if let url = item as? URL {
            text = url.absoluteString
        } else if let value = item as? String {
            text = value
        } else {
            throw ShareLoadError.emptyItem
        }

        return ShareDraft(type: "link", text: text, data: nil, fileName: nil)
    }

    private static func loadImage(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> ShareDraft {
        let data = try await loadData(
            from: provider,
            typeIdentifier: typeIdentifier
        )

        let type = UTType(typeIdentifier)
        let fileName = fileName(
            suggestedName: provider.suggestedName,
            fallback: "Shared Image",
            type: type
        )
        return ShareDraft(type: "image", text: nil, data: data, fileName: fileName)
    }

    private static func loadFileURL(from provider: NSItemProvider) async throws -> ShareDraft {
        let item = try await loadItem(
            from: provider,
            typeIdentifier: UTType.fileURL.identifier
        )

        let url: URL
        if let value = item as? URL {
            url = value
        } else if let value = item as? String, let parsed = URL(string: value) {
            url = parsed
        } else {
            throw ShareLoadError.emptyItem
        }

        return ShareDraft(
            type: "file",
            text: nil,
            data: try Data(contentsOf: url),
            fileName: url.lastPathComponent
        )
    }

    private static func loadFile(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> ShareDraft {
        let data = try await loadData(
            from: provider,
            typeIdentifier: typeIdentifier
        )
        let type = UTType(typeIdentifier)
        let fileName = fileName(
            suggestedName: provider.suggestedName,
            fallback: "Shared File",
            type: type
        )
        return ShareDraft(type: "file", text: nil, data: data, fileName: fileName)
    }

    private static func loadItem(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: typeIdentifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: ShareLoadError.emptyItem)
                }
            }
        }
    }

    private static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ShareLoadError.emptyItem)
                }
            }
        }
    }

    private static func firstRegisteredType(
        in provider: NSItemProvider,
        conformingTo parentType: UTType
    ) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: parentType) == true
        }
    }

    private static func firstRegisteredFileType(in provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .data)
                && !type.conforms(to: .text)
                && !type.conforms(to: .url)
                && !type.conforms(to: .image)
        }
    }

    private static func fileName(
        suggestedName: String?,
        fallback: String,
        type: UTType?
    ) -> String {
        let name = suggestedName ?? fallback
        guard URL(fileURLWithPath: name).pathExtension.isEmpty,
              let fileExtension = type?.preferredFilenameExtension else {
            return name
        }
        return "\(name).\(fileExtension)"
    }
}

enum ShareSnapshotReader {
    static func loadPinboards() throws -> [SharePinboard] {
        guard FileManager.default.fileExists(atPath: ShareSharedPaths.store.path) else {
            return []
        }
        let data = try Data(contentsOf: ShareSharedPaths.store)
        return try JSONDecoder().decode(ShareSnapshot.self, from: data).pinboards
    }
}

enum ShareOutboxWriter {
    static func append(_ drafts: [ShareDraft], pinboardID: UUID?) throws {
        try FileManager.default.createDirectory(
            at: ShareSharedPaths.payloadDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for draft in drafts {
            let id = UUID()
            let payloadFileName = draft.data.map { _ in "\(id.uuidString).payload" }
            if let data = draft.data, let payloadFileName {
                try data.write(
                    to: ShareSharedPaths.payloadDirectory
                        .appendingPathComponent(payloadFileName),
                    options: .atomic
                )
            }

            let entry = ShareOutboxEntry(
                id: id,
                type: draft.type,
                text: draft.text,
                payloadFileName: payloadFileName,
                fileName: draft.fileName,
                createdAt: Date(),
                pinboardID: pinboardID
            )
            let entryURL = ShareSharedPaths.outboxDirectory
                .appendingPathComponent("\(id.uuidString).json")
            try encoder.encode(entry).write(to: entryURL, options: .atomic)
        }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    @Published private(set) var drafts: [ShareDraft] = []
    @Published private(set) var pinboards: [SharePinboard] = []
    @Published var selectedPinboardID: UUID?
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let providers: [NSItemProvider]

    init(providers: [NSItemProvider]) {
        self.providers = providers
    }

    var canSave: Bool {
        !isLoading && !isSaving && !drafts.isEmpty
    }

    func load() {
        Task {
            do {
                pinboards = try ShareSnapshotReader.loadPinboards()

                var loaded: [ShareDraft] = []
                for provider in providers {
                    loaded.append(try await SharePayloadLoader.load(from: provider))
                }
                guard !loaded.isEmpty else {
                    throw ShareLoadError.emptyItem
                }
                drafts = loaded
                isLoading = false
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func save() throws {
        isSaving = true
        defer { isSaving = false }

        try ShareOutboxWriter.append(drafts, pinboardID: selectedPinboardID)
    }
}
