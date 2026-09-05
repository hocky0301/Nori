import AppKit
import Foundation

enum TestImages {
    static func png(width: Int, height: Int, color: NSColor = .systemOrange) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// A deterministic photo-like fixture (smooth two-axis gradient) so thumbnail sizes mean something;
    /// a flat colour would compress to nothing.
    static func gradient(width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let pixels = rep.bitmapData else { return nil }
        let rowBytes = rep.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                pixels[offset] = UInt8(x * 255 / max(width - 1, 1))
                pixels[offset + 1] = UInt8(y * 255 / max(height - 1, 1))
                pixels[offset + 2] = UInt8(((x + y) * 255 / max(width + height - 2, 1)) & 0xFF)
                pixels[offset + 3] = 255
            }
        }
        return rep.representation(using: .png, properties: [:])
    }
}
