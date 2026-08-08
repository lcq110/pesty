import AppKit
import XCTest
@testable import Pesty

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testCapturesHTMLAsRichText() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PestyTests.\(UUID().uuidString)")
        )
        let html = Data("<strong>Formatted</strong>".utf8)
        pasteboard.clearContents()
        pasteboard.setData(html, forType: .html)
        pasteboard.setString("Formatted", forType: .string)

        let item = try XCTUnwrap(ClipboardMonitor().makeItem(from: pasteboard))

        XCTAssertEqual(item.type, .richText)
        XCTAssertEqual(item.htmlData, html)
        XCTAssertEqual(item.text, "Formatted")

        let formattedPasteboard = makePasteboard()
        PasteService.copy(item, mode: .formatted, to: formattedPasteboard)
        XCTAssertEqual(formattedPasteboard.data(forType: .html), html)
        XCTAssertEqual(formattedPasteboard.string(forType: .string), "Formatted")

        let plainPasteboard = makePasteboard()
        PasteService.copy(item, mode: .plainText, to: plainPasteboard)
        XCTAssertNil(plainPasteboard.data(forType: .html))
        XCTAssertEqual(plainPasteboard.string(forType: .string), "Formatted")
    }

    func testCapturesHTMLWithoutPlainTextType() throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(
            Data("<html><body><strong>HTML only</strong></body></html>".utf8),
            forType: .html
        )

        let item = try XCTUnwrap(ClipboardMonitor().makeItem(from: pasteboard))

        XCTAssertEqual(item.type, .richText)
        XCTAssertEqual(
            item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            "HTML only"
        )
    }

    func testCapturesRTFWithoutPlainTextType() throws {
        let pasteboard = makePasteboard()
        let attributed = NSAttributedString(string: "RTF only")
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)

        let item = try XCTUnwrap(ClipboardMonitor().makeItem(from: pasteboard))

        XCTAssertEqual(item.type, .richText)
        XCTAssertEqual(item.text, "RTF only")
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("PestyTests.\(UUID().uuidString)"))
    }
}
