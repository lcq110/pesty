import Foundation
import Testing
@testable import PestyShared

@Suite
struct CloudKitAssetSyncServiceTests {
    @Test
    func testCachedFileURLAndResolution() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PestyAssetTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let filesDirectory = directory.appendingPathComponent("files")
        let item = ClipItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            type: .file,
            fileURLs: ["file:///missing/Quarterly%20Report.pdf"]
        )
        let cached = CloudKitAssetSyncService.cachedFileURL(
            for: item,
            index: 0,
            filesDirectory: filesDirectory
        )

        #expect(
            cached.lastPathComponent
                == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE-0-Quarterly Report.pdf"
        )
        #expect(
            CloudKitAssetSyncService.resolvedFileURLs(
                for: item,
                filesDirectory: filesDirectory
            ).isEmpty
        )

        try FileManager.default.createDirectory(
            at: filesDirectory,
            withIntermediateDirectories: true
        )
        try Data("asset".utf8).write(to: cached)

        #expect(
            CloudKitAssetSyncService.resolvedFileURLs(
                for: item,
                filesDirectory: filesDirectory
            ) == [cached]
        )
    }
}
