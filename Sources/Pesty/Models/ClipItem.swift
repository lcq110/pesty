import Foundation
import PestyShared

typealias ClipItem = PestyShared.ClipItem

extension ClipItem {
    func editedCopy(with text: String, createdAt: Date = Date()) -> ClipItem {
        ClipItem(
            type: .inferred(fromPlainText: text),
            text: text,
            createdAt: createdAt
        )
    }
}
