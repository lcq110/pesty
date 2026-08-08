import AppKit
import XCTest
@testable import Pesty

@MainActor
final class PasteServiceTests: XCTestCase {
    func testFormattedRichTextWritesRTFAndString() {
        let pasteboard = makePasteboard()
        let rtf = Data("{\\rtf1 Formatted}".utf8)
        let item = ClipItem(type: .richText, text: "Formatted", rtfData: rtf)

        PasteService.copy(item, mode: .formatted, to: pasteboard)

        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(pasteboard.string(forType: .string), "Formatted")
    }

    func testCopyDefaultsToFormatted() {
        let pasteboard = makePasteboard()
        let rtf = Data("{\\rtf1 Default}".utf8)
        let item = ClipItem(type: .richText, text: "Default", rtfData: rtf)

        PasteService.copy(item, to: pasteboard)

        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(pasteboard.string(forType: .string), "Default")
    }

    func testPlainTextRichTextWritesOnlyString() {
        let pasteboard = makePasteboard()
        let item = ClipItem(
            type: .richText,
            text: "Plain",
            rtfData: Data("{\\rtf1 Plain}".utf8)
        )

        PasteService.copy(item, mode: .plainText, to: pasteboard)

        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertEqual(pasteboard.string(forType: .string), "Plain")
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("PestyTests.\(UUID().uuidString)"))
    }
}
