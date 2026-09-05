import AppKit

/// Computes where the panel should appear for each `NoriSettings.PanelPosition`.
@MainActor
enum PanelPlacement {
    static func origin(
        for size: NSSize,
        position: NoriSettings.PanelPosition,
        statusButton: NSStatusBarButton?,
        lastOrigin: NSPoint?
    ) -> NSPoint {
        switch position {
        case .center:
            if let frame = NSScreen.main?.visibleFrame {
                return centered(size, in: frame)
            }
        case .activeWindow:
            if let frame = frontmostWindowFrame() {
                return constrain(centered(size, in: frame), size: size, to: screen(containing: frame))
            }
        case .statusItem:
            if let button = statusButton, let window = button.window {
                let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
                let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 6)
                return constrain(origin, size: size, to: window.screen)
            }
        case .lastPosition:
            if let lastOrigin {
                return constrain(lastOrigin, size: size, to: screen(containing: NSRect(origin: lastOrigin, size: size)))
            }
        case .cursor:
            break
        }

        // Default: top-left corner of the panel at the pointer, nudged so the pointer sits inside the first row.
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x - 24, y: mouse.y - size.height + 24)
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return constrain(origin, size: size, to: screen)
    }

    static func centered(_ size: NSSize, in frame: NSRect) -> NSPoint {
        NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.08)
    }

    /// Keep the whole panel on one screen.
    static func constrain(_ origin: NSPoint, size: NSSize, to screen: NSScreen?) -> NSPoint {
        guard let frame = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - size.width)),
            y: min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - size.height))
        )
    }

    static func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { $0.frame.intersection(rect).area < $1.frame.intersection(rect).area } ?? NSScreen.main
    }

    /// Frame of the frontmost app's front window, in AppKit screen coordinates.
    static func frontmostWindowFrame() -> NSRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
                  w > 100, h > 100 else { continue }
            // CGWindow coordinates are top-left based; flip into AppKit's bottom-left space.
            return NSRect(x: x, y: primary.frame.height - y - h, width: w, height: h)
        }
        return nil
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
