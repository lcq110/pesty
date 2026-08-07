import XCTest
@testable import Pesty

final class ClipEditingTests: XCTestCase {
    func testEditedRichTextCreatesANewPlainTextCard() {
        let original = ClipItem(
            type: .richText,
            text: "Original",
            rtfData: Data("formatted".utf8)
        )
        let date = Date(timeIntervalSince1970: 123)

        let copy = original.editedCopy(with: "Edited", createdAt: date)

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.type, .text)
        XCTAssertEqual(copy.text, "Edited")
        XCTAssertNil(copy.rtfData)
        XCTAssertEqual(copy.createdAt, date)
        XCTAssertEqual(original.text, "Original")
    }

    func testEditedURLCreatesALinkCard() {
        let original = ClipItem(type: .text, text: "Original")

        let copy = original.editedCopy(with: "https://example.com/path")

        XCTAssertEqual(copy.type, .link)
    }
}
