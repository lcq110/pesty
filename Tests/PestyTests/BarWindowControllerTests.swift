import AppKit
import XCTest
@testable import Pesty

@MainActor
final class BarWindowControllerTests: XCTestCase {
    func testPasteBarCanAppearWithoutActivatingPestyOnEverySpace() {
        XCTAssertTrue(BarPanel.presentationStyleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(BarPanel.spaceCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(BarPanel.spaceCollectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(BarPanel.spaceCollectionBehavior.contains(.moveToActiveSpace))
    }
}
