import Foundation

public enum SharedSnapshotStoreError: Error, Equatable {
    case appGroupUnavailable(String)
}

public struct SharedSnapshotStore: Sendable {
    public let snapshotURL: URL

    public init(
        appGroupIdentifier: String,
        fileName: String = "store.json"
    ) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedSnapshotStoreError.appGroupUnavailable(appGroupIdentifier)
        }
        self.init(directoryURL: containerURL, fileName: fileName)
    }

    public init(
        directoryURL: URL,
        fileName: String = "store.json"
    ) {
        snapshotURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    public func load() throws -> PestySnapshot? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return nil
        }
        return try SnapshotCoding.decoder.decode(
            PestySnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
    }

    public func save(_ snapshot: PestySnapshot) throws {
        let directoryURL = snapshotURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try SnapshotCoding.encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
    }
}

enum SnapshotCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        JSONDecoder()
    }
}
