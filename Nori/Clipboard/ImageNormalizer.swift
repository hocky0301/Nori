import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Every screenshot arrives as a 30 MB TIFF plus a 300 KB PNG. Nori keeps PNG only, and a
/// small inline thumbnail so the list never decodes a full image.
enum ImageNormalizer {
    struct Result: Sendable, Equatable {
        var png: Data
        var pixelSize: CGSize
        var thumbnail: Data?
    }

    static let thumbnailMaxPixelSize = 224

    /// Pick the PNG representation or transcode the first decodable one to PNG.
    static func normalize(contents: [ClipDraft.Content]) -> Result? {
        let png = contents.first { $0.type == PasteboardType.png }?.data
        let source = png ?? contents.first { PasteboardType.imageTypes.contains($0.type) }?.data
        guard let source else { return nil }

        let pngData: Data
        if let png {
            pngData = png
        } else if let transcoded = transcodeToPNG(source) {
            pngData = transcoded
        } else {
            return nil
        }
        guard let size = pixelSize(of: pngData) else { return nil }
        return Result(png: pngData, pixelSize: size, thumbnail: thumbnail(from: pngData))
    }

    static func pixelSize(of imageData: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    static func transcodeToPNG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return encodePNG(image)
    }

    static func thumbnail(from data: Data, maxPixelSize: Int = thumbnailMaxPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodePNG(thumb)
    }

    /// Downsampled decode for the expanded preview (never the full 4K bitmap).
    static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
