import PestyShared
import SwiftUI

enum PestyTheme {
    static let tint = Color(red: 0.36, green: 0.50, blue: 0.98)
    static let secondaryTint = Color(red: 0.60, green: 0.46, blue: 0.98)
    static let cardCornerRadius: CGFloat = 18

    static func color(for type: ClipType) -> Color {
        switch type {
        case .text: Color(red: 0.39, green: 0.55, blue: 0.98)
        case .richText: Color(red: 0.60, green: 0.46, blue: 0.98)
        case .link: Color(red: 0.20, green: 0.74, blue: 0.62)
        case .image: Color(red: 0.96, green: 0.62, blue: 0.26)
        case .file: Color(red: 0.91, green: 0.44, blue: 0.47)
        case .color: Color(red: 0.55, green: 0.78, blue: 0.34)
        }
    }

    static func symbol(for type: ClipType) -> String {
        switch type {
        case .text: "text.alignleft"
        case .richText: "doc.richtext"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }

    static func label(for type: ClipType) -> String {
        switch type {
        case .text: "Text"
        case .richText: "Rich Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        case .color: "Color"
        }
    }
}

extension ClipItem {
    var mobileTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }

        if type == .file, let first = fileURLs.first {
            return URL(string: first)?.lastPathComponent ?? text ?? "File"
        }

        if type == .image {
            return imageFileName ?? "Image"
        }

        if type == .link,
           let text,
           let host = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host {
            return host
        }

        let firstLine = (text ?? "")
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        return firstLine.isEmpty ? PestyTheme.label(for: type) : String(firstLine.prefix(80))
    }

    var mobileSearchText: String {
        [
            customTitle,
            text,
            sourceAppName,
            sourceBundleID,
            fileURLs.joined(separator: " "),
            colorHex
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}
