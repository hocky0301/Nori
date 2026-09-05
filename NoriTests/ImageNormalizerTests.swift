import AppKit
import Foundation
import Testing
@testable import Nori

/// Screenshots arrive as a huge TIFF plus a PNG; Nori keeps PNG only and a small inline thumbnail.
@Suite("ImageNormalizer")
struct ImageNormalizerTests {
    private func content(_ type: String, _ data: Data) -> ClipDraft.Content { .init(type: type, data: data) }

    @Test func pngPlusTIFFKeepsThePNGBytesUntouched() throws {
        let png = try #require(TestImages.gradient(width: 320, height: 200))
        let tiff = try #require(NSImage(data: png)?.tiffRepresentation)
        #expect(tiff.count > png.count)
        let result = try #require(ImageNormalizer.normalize(contents: [content(PasteboardType.tiff, tiff), content(PasteboardType.png, png)]))
        #expect(result.png == png, "an existing PNG is stored as-is, never re-encoded")
        #expect(result.pixelSize == CGSize(width: 320, height: 200))
        #expect(ImageNormalizer.pixelSize(of: result.png) == result.pixelSize)
    }

    @Test func tiffOnlyIsTranscodedToPNG() throws {
        let png = try #require(TestImages.gradient(width: 64, height: 48))
        let tiff = try #require(NSImage(data: png)?.tiffRepresentation)
        let result = try #require(ImageNormalizer.normalize(contents: [content(PasteboardType.tiff, tiff)]))
        #expect(result.pixelSize == CGSize(width: 64, height: 48))
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A
        #expect(Array(result.png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(result.thumbnail != nil)
    }

    @Test func jpegIsTranscodedToPNGToo() throws {
        let png = try #require(TestImages.gradient(width: 50, height: 20))
        let jpeg = try #require(NSBitmapImageRep(data: png)?.representation(using: .jpeg, properties: [:]))
        let result = try #require(ImageNormalizer.normalize(contents: [content(PasteboardType.jpeg, jpeg)]))
        #expect(Array(result.png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        #expect(result.pixelSize == CGSize(width: 50, height: 20))
    }

    @Test func nonImageContentsYieldNothing() throws {
        #expect(ImageNormalizer.normalize(contents: [content(PasteboardType.utf8PlainText, Data("hi".utf8))]) == nil)
        #expect(ImageNormalizer.normalize(contents: [content(PasteboardType.tiff, Data("not a tiff".utf8))]) == nil)
        #expect(ImageNormalizer.normalize(contents: []) == nil)
    }

    @Test func thumbnailOfAScreenshotIsSmall() throws {
        let png = try #require(TestImages.gradient(width: 1440, height: 900))
        let result = try #require(ImageNormalizer.normalize(contents: [content(PasteboardType.png, png)]))
        #expect(result.pixelSize == CGSize(width: 1440, height: 900))
        let thumbnail = try #require(result.thumbnail)
        let size = try #require(ImageNormalizer.pixelSize(of: thumbnail))
        #expect(size.width <= 224 && size.height <= 224)
        #expect(size.width == 224, "the long side fills the budget")
        #expect(abs(size.height - 140) <= 1, "aspect ratio is preserved: \(size)")
        #expect(thumbnail.count <= 60 * 1024, "thumbnail is \(thumbnail.count) bytes")
        #expect(thumbnail.count < png.count)
    }

    @Test func thumbnailNeverUpscales() throws {
        let png = try #require(TestImages.gradient(width: 40, height: 30))
        let thumbnail = try #require(ImageNormalizer.thumbnail(from: png))
        #expect(ImageNormalizer.pixelSize(of: thumbnail) == CGSize(width: 40, height: 30))
    }

    @Test func decodeDownsamplesToTheRequestedBudget() throws {
        let png = try #require(TestImages.gradient(width: 1440, height: 900))
        let image = try #require(ImageNormalizer.decode(png, maxPixelSize: 300))
        #expect(image.width == 300)
        #expect(abs(image.height - 188) <= 1, "got \(image.height)")

        let full = try #require(ImageNormalizer.decode(png, maxPixelSize: 4096))
        #expect(full.width == 1440 && full.height == 900, "a budget above the image size keeps it whole")
        #expect(ImageNormalizer.decode(Data([1, 2, 3]), maxPixelSize: 300) == nil)
    }

    @Test func pixelSizeOfGarbageIsNil() {
        #expect(ImageNormalizer.pixelSize(of: Data()) == nil)
        #expect(ImageNormalizer.pixelSize(of: Data("definitely not an image".utf8)) == nil)
        #expect(ImageNormalizer.pixelSize(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])) == nil, "a bare PNG signature is not an image")
        #expect(ImageNormalizer.transcodeToPNG(Data(repeating: 0xFF, count: 64)) == nil)
    }
}
