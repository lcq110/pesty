import AppKit
import XCTest
@testable import Pesty

@MainActor
final class BarWindowControllerTests: XCTestCase {
    func testPasteBarMovesToTheActiveSpace() {
        XCTAssertTrue(BarPanel.presentationStyleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(BarPanel.spaceCollectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(BarPanel.spaceCollectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(BarPanel.spaceCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(BarPanel.spaceCollectionBehavior.contains(.stationary))
    }
}
