import CoreSpotlight
import Foundation
import PestyShared
import UniformTypeIdentifiers

enum SpotlightIndexer {
    private static let domainIdentifier = "com.greycorelabs.pesty.clips"

    static func index(_ clips: [ClipItem]) {
        let items = clips.prefix(1_000).map { clip in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = clip.mobileTitle
            attributes.contentDescription = clip.text
            attributes.keywords = [
                PestyTheme.label(for: clip.type),
                clip.sourceAppName,
                clip.colorHex
            ].compactMap { $0 }

            return CSSearchableItem(
                uniqueIdentifier: clip.id.uuidString,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }

        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items)
        }
    }
}
