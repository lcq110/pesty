import Foundation
import PestyShared
import Testing
@testable import PestyMobile

struct MobilePresentationTests {
    @Test
    func customTitleWins() {
        let item = ClipItem(
            type: .text,
            text: "Original text",
            customTitle: "Pinned reply"
        )

        #expect(item.mobileTitle == "Pinned reply")
    }

    @Test
    func linkUsesHostAsTitle() {
        let item = ClipItem(
            type: .link,
            text: "https://github.com/momenbasel/pesty"
        )

        #expect(item.mobileTitle == "github.com")
    }

    @Test
    func searchIncludesSourceApplication() {
        let item = ClipItem(
            type: .text,
            text: "Quarterly notes",
            sourceBundleID: "com.apple.mobilesafari",
            sourceAppName: "Safari"
        )

        #expect(item.mobileSearchText.contains("safari"))
    }
}
