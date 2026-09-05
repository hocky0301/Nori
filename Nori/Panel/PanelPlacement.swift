import AppKit

/// Where and how big the panel is for each `NoriSettings.PanelPosition`.
@MainActor
enum PanelPlacement {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 320
    static let maxHeight: CGFloat = 620

    /// 75 % of the screen's visible height, clamped. Computed once per open; never changes while open.
    static func height(for screen: NSScreen?) -> CGFloat {
        let visible = screen?.visibleFrame.height ?? 900
        return min(max(floor(visible * 0.75), minHeight), maxHeight)
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    static func frame(position: NoriSettings.PanelPosition, statusButton: NSStatusBarButton?) -> NSRect {
        let screen = screenUnderMouse()
        let size = NSSize(width: width, height: height(for: screen))
        let origin: NSPoint
        switch position {
        case .center:
            let frame = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.22 - size.height)
        case .statusItem:
            if let button = statusButton, let window = button.window {
                let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
                origin = constrain(NSPoint(x: rect.minX, y: rect.minY - size.height - 4), size: size, to: window.screen)
            } else {
                origin = cursorOrigin(size: size, screen: screen)
            }
        case .cursor:
            origin = cursorOrigin(size: size, screen: screen)
        }
        return NSRect(origin: origin, size: size)
    }

    private static func cursorOrigin(size: NSSize, screen: NSScreen?) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        // Top-left corner at the pointer, nudged so the pointer sits inside the first row.
        return constrain(NSPoint(x: mouse.x - 20, y: mouse.y - size.height + 20), size: size, to: screen)
    }

    /// Keep the whole panel on one screen.
    static func constrain(_ origin: NSPoint, size: NSSize, to screen: NSScreen?) -> NSPoint {
        guard let frame = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - size.width)),
            y: min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - size.height))
        )
    }
}
