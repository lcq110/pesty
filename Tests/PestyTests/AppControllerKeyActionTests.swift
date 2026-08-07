import AppKit
import XCTest
@testable import Pesty

@MainActor
final class AppControllerKeyActionTests: XCTestCase {
    func testReturnPastesWithoutShift() {
        XCTAssertEqual(AppController.returnKeyAction(for: []), .paste)
    }

    func testShiftReturnCopies() {
        XCTAssertEqual(AppController.returnKeyAction(for: [.shift]), .copy)
    }
}
