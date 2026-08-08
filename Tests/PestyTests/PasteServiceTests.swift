import AppKit
import XCTest
@testable import Pesty

@MainActor
final class PasteServiceTests: XCTestCase {
    func testFormattedRichTextWritesRTFAndString() {
        let pasteboard = makePasteboard()
        let rtf = Data("{\\rtf1 Formatted}".utf8)
        let html = Data("<b>Formatted</b>".utf8)
        let item = ClipItem(
            type: .richText,
            text: "Formatted",
            rtfData: rtf,
            htmlData: html
        )

        PasteService.copy(item, mode: .formatted, to: pasteboard)

        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(pasteboard.data(forType: .html), html)
        XCTAssertEqual(pasteboard.data(forType: .legacyHTML), html)
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

    func testFormattedLegacyRTFAlsoWritesHTML() throws {
        let attributed = NSAttributedString(
            string: "Legacy",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        )
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let item = ClipItem(type: .richText, text: "Legacy", rtfData: rtf)
        let pasteboard = makePasteboard()

        PasteService.copy(item, mode: .formatted, to: pasteboard)

        XCTAssertNotNil(pasteboard.data(forType: .html))
        XCTAssertEqual(pasteboard.string(forType: .string), "Legacy")
    }

    func testPlainTextRichTextWritesOnlyString() {
        let pasteboard = makePasteboard()
        let item = ClipItem(
            type: .richText,
            text: "Plain",
            rtfData: Data("{\\rtf1 Plain}".utf8),
            htmlData: Data("<b>Plain</b>".utf8)
        )

        PasteService.copy(item, mode: .plainText, to: pasteboard)

        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: .html))
        XCTAssertNil(pasteboard.data(forType: .legacyHTML))
        XCTAssertEqual(pasteboard.string(forType: .string), "Plain")
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("PestyTests.\(UUID().uuidString)"))
    }
}
