import PestyShared
import SwiftUI

struct ClipCard: View {
    @Environment(MobileClipboardStore.self) private var store
    let item: ClipItem

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            preview
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.mobileTitle)
                    .font(.headline)
                    .lineLimit(2)

                if let detail = detailText, detail != item.mobileTitle {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 7) {
                    Label(
                        PestyTheme.label(for: item.type),
                        systemImage: PestyTheme.symbol(for: item.type)
                    )
                    if let source = item.sourceAppName, !source.isEmpty {
                        Text("•")
                        Text(source)
                    }
                    Text("•")
                    Text(item.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .draggable(item.text ?? item.mobileTitle)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap and hold for clip actions")
    }

    @ViewBuilder
    private var preview: some View {
        if item.type == .image,
           let data = store.imageData(for: item),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if item.type == .color, let hex = item.colorHex {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hexString: hex) ?? PestyTheme.color(for: item.type))
                .overlay {
                    Text(hex)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PestyTheme.color(for: item.type).opacity(0.16))
                .overlay {
                    Image(systemName: PestyTheme.symbol(for: item.type))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PestyTheme.color(for: item.type))
                }
        }
    }

    private var detailText: String? {
        switch item.type {
        case .image:
            item.customTitle
        case .file:
            item.fileURLs.first.flatMap { URL(string: $0)?.lastPathComponent } ?? item.text
        case .color:
            item.colorHex
        default:
            item.text
        }
    }
}

extension Color {
    init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let number = UInt64(value, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}
