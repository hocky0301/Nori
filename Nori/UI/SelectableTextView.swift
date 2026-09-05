import AppKit
import SwiftUI

/// A selectable, non-editable, scrollable `NSTextView` for the expanded text/code preview.
struct SelectableTextView: NSViewRepresentable {
    let text: String
    let monospaced: Bool

    static let maxCharacters = 10_000

    var font: NSFont {
        monospaced ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
    }

    /// Inside the glass hosting view, vibrant text blends with the backdrop and reads washed out.
    final class PreviewTextView: NSTextView {
        override var allowsVibrancy: Bool { false }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PreviewTextView(frame: .zero)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 0, height: 2)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.isAutomaticLinkDetectionEnabled = false
            textView.usesFindPanel = false
            textView.allowsUndo = false
            textView.setAccessibilityLabel("Preview")
        }
        apply(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        apply(to: scrollView)
    }

    private func apply(to scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scroll(.zero)
        }
        textView.font = font
        textView.textColor = .labelColor
    }

    /// Height the text would need at `width`, so the card grows only as much as necessary.
    static func measuredHeight(of text: String, monospaced: Bool, width: CGFloat) -> CGFloat {
        let font: NSFont = monospaced ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height) + 4
    }
}
