import ImageIO
import SwiftUI

actor ImagePreviewProvider {
    static let shared = ImagePreviewProvider()

    private let cache: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.countLimit = 64
        return cache
    }()

    func image(at url: URL) -> CGImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct ClipImagePreview: View {
    let url: URL?

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = if let url {
                await ImagePreviewProvider.shared.image(at: url)
            } else {
                nil
            }
        }
    }
}
