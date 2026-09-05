import SwiftUI

/// Spacing tokens from the spec (§10), on a 4 pt grid.
enum PanelMetrics {
    static let inset: CGFloat = 12
    static let rowGap: CGFloat = 8
    static let cardGap: CGFloat = 4
    static let cardPadV: CGFloat = 8
    static let cardPadH: CGFloat = 12
    static let wellSize: CGFloat = 28
    static let thumbSize: CGFloat = 56
    static let wellGap: CGFloat = 10
    static let metaGap: CGFloat = 8
    static let metaWidth: CGFloat = 128
    static let sectionAbove: CGFloat = 16
    static let sectionBelow: CGFloat = 6
    static let hintGap: CGFloat = 10
    static let searchHeight: CGFloat = 36
    static let chipHeight: CGFloat = 24
    static let hintBarHeight: CGFloat = 28
    static let ghostHeight: CGFloat = 32
    /// The expanded card grows in place up to this height.
    static let expandedCardMaxHeight: CGFloat = 300
    /// Room left for the preview body once the summary row and meta strip are subtracted.
    static let previewMaxHeight: CGFloat = 196
    /// Card width minus its horizontal padding.
    static let cardContentWidth: CGFloat = 560 - 2 * inset - 2 * cardPadH

    enum Radius {
        static let panel: CGFloat = 22
        static let card: CGFloat = 12
        static let well: CGFloat = 7
        static let thumb: CGFloat = 8
        static let search: CGFloat = 18
        static let chip: CGFloat = 12
        static let keycap: CGFloat = 5
        static let ghost: CGFloat = 8
    }
}

/// Color roles (§10): semantic colors only; light and dark differ in the opacity steps.
struct PanelTheme {
    let isDark: Bool

    var cardGround: Color { .primary.opacity(isDark ? 0.06 : 0.04) }
    var cardSelectedFill: Color { .accentColor.opacity(isDark ? 0.28 : 0.22) }
    var cardSelectedStroke: Color { .accentColor.opacity(isDark ? 0.40 : 0.35) }
    var cardExpandedGround: Color { .primary.opacity(isDark ? 0.08 : 0.06) }
    var cardExpandedStroke: Color { .accentColor.opacity(isDark ? 0.35 : 0.30) }
    var searchPill: Color { .primary.opacity(isDark ? 0.08 : 0.06) }
    var keycapFill: Color { .primary.opacity(isDark ? 0.10 : 0.08) }
    var keycapStroke: Color { .primary.opacity(isDark ? 0.14 : 0.12) }
    var toastFill: Color { .primary.opacity(isDark ? 0.14 : 0.10) }
    var hover: Color { .primary.opacity(0.06) }
    var matchHighlight: Color { .accentColor.opacity(isDark ? 0.35 : 0.25) }
    var hairline: Color { .primary.opacity(0.10) }
    var wellTintOpacity: Double { 0.12 }
}

/// Motion table (§10) with the Reduce Motion column applied.
struct PanelMotion {
    let reduce: Bool

    var expand: Animation { reduce ? .easeOut(duration: 0.15) : .spring(duration: 0.30, bounce: 0.15) }
    var rows: Animation { reduce ? .easeInOut(duration: 0.15) : .snappy }
    var crossfade: Animation { .easeInOut(duration: 0.12) }
    var hint: Animation { .easeInOut(duration: 0.10) }
    var keycap: Animation { .easeInOut(duration: 0.10) }
    var press: Animation { .easeOut(duration: 0.08) }
    var toastIn: Animation { .easeOut(duration: 0.15) }
    var toastOut: Animation { .easeIn(duration: 0.20) }

    var rowTransition: AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity)
    }

    var toastTransition: AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
}

extension EnvironmentValues {
    var panelTheme: PanelTheme { PanelTheme(isDark: colorScheme == .dark) }
    var panelMotion: PanelMotion { PanelMotion(reduce: accessibilityReduceMotion) }
}

extension ClipKind {
    /// Type tint, used only inside the well (§10).
    var tint: Color {
        switch self {
        case .text: .secondary
        case .link: .blue
        case .code: .indigo
        case .color: .orange
        case .image: .teal
        case .file: .secondary
        }
    }
}

extension Font {
    static let cardTitle = Font.system(size: 13)
    static let cardSecondary = Font.system(size: 12)
    static let linkHost = Font.system(size: 13, weight: .semibold)
    static let code = Font.system(size: 12, design: .monospaced)
    static let colorHex = Font.system(size: 13, design: .monospaced)
    static let meta = Font.system(size: 11, weight: .medium)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let keycap = Font.system(size: 11, weight: .medium)
    static let search = Font.system(size: 14)
    static let hint = Font.system(size: 11)
    static let toast = Font.system(size: 12, weight: .medium)
    static let emptyTitle = Font.system(size: 15, weight: .semibold)
    static let emptyBody = Font.system(size: 13)
    static let chip = Font.system(size: 12, weight: .medium)
    static let chipSelected = Font.system(size: 12, weight: .semibold)
    static let ghost = Font.system(size: 11)
}
