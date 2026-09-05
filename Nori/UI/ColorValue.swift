import SwiftUI

/// A normalized `#RRGGBB` / `#RRGGBBAA` value with its rgb() and hsl() spellings for display.
struct ColorValue: Hashable, Sendable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    init?(hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 || digits.count == 4 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        if digits.count == 8 {
            red = Int((value >> 24) & 0xFF)
            green = Int((value >> 16) & 0xFF)
            blue = Int((value >> 8) & 0xFF)
            alpha = Int(value & 0xFF)
        } else {
            red = Int((value >> 16) & 0xFF)
            green = Int((value >> 8) & 0xFF)
            blue = Int(value & 0xFF)
            alpha = 255
        }
    }

    var hasAlpha: Bool { alpha < 255 }

    var hexString: String {
        hasAlpha
            ? String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
            : String(format: "#%02X%02X%02X", red, green, blue)
    }

    private var alphaFraction: String {
        let value = Double(alpha) / 255
        return String(format: value == value.rounded() ? "%.0f" : "%.2f", value)
    }

    var rgbString: String {
        hasAlpha
            ? "rgba(\(red), \(green), \(blue), \(alphaFraction))"
            : "rgb(\(red), \(green), \(blue))"
    }

    var hslString: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let l = (maxC + minC) / 2
        var h = 0.0
        var s = 0.0
        if delta > 0 {
            s = delta / (1 - abs(2 * l - 1))
            switch maxC {
            case r: h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: h = (b - r) / delta + 2
            default: h = (r - g) / delta + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        let hue = Int(h.rounded()), sat = Int((s * 100).rounded()), light = Int((l * 100).rounded())
        return hasAlpha
            ? "hsla(\(hue), \(sat)%, \(light)%, \(alphaFraction))"
            : "hsl(\(hue), \(sat)%, \(light)%)"
    }

    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: Double(alpha) / 255)
    }

    /// Relative luminance, for picking a legible overlay on a swatch.
    var isLight: Bool {
        (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255 > 0.6
    }
}

/// Alpha swatches sit on a checkerboard so transparency is visible.
struct Checkerboard: View {
    var cell: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.18)))
                }
            }
        }
        .background(Color.white.opacity(0.9))
    }
}

/// A color swatch with a hairline and a checkerboard behind translucent values.
struct ColorSwatch: View {
    let value: ColorValue
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(value.color)
            .background {
                if value.hasAlpha {
                    Checkerboard().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .frame(width: size, height: size)
    }
}
