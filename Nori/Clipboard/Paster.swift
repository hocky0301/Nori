import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog

/// Sends ⌘V to the frontmost app. Needs the Accessibility permission.
enum Paster {
    private static let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "paste")

    /// Whether macOS lets Nori synthesise keystrokes. Re-read on every action: trust drifts after rebuilds.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask macOS to show the Accessibility prompt (once per app signature).
    @MainActor
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Post ⌘V. Returns false when the permission is missing (the caller should fall back to copy-only).
    @discardableResult
    static func sendPasteKeystroke() -> Bool {
        guard isTrusted else {
            logger.notice("paste skipped: Accessibility permission not granted")
            return false
        }
        let keyCode = KeyCodeLookup.commandV()
        let source = CGEventSource(stateID: .combinedSessionState)
        // Stop the user's physical modifier state from bleeding into the synthetic event.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        // 0x8 marks the left-side device modifier; some apps ignore ⌘ without it (Flycut #18).
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0008)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        usleep(10_000)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}

/// Finds the virtual key code that produces a character under the *current* keyboard layout,
/// so ⌘V still means "paste" on Dvorak, Colemak, AZERTY or JIS layouts.
enum KeyCodeLookup {
    /// The key that yields "v" on the ⌘ layer (handles "Dvorak – QWERTY ⌘"), falling back to ANSI V.
    static func commandV() -> CGKeyCode {
        keyCode(for: "v", withCommand: true) ?? keyCode(for: "v", withCommand: false) ?? CGKeyCode(kVK_ANSI_V)
    }

    static func keyCode(for character: Character, withCommand: Bool = false) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        let target = String(character).lowercased()
        let modifierState: UInt32 = withCommand ? UInt32((cmdKey >> 8) & 0xFF) : 0

        return layoutData.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var buffer = [UniChar](repeating: 0, count: 4)
            var length = 0
            for code in 0..<128 {
                deadKeyState = 0
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), modifierState,
                    UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState, buffer.count, &length, &buffer
                )
                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: buffer, count: length).lowercased() == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
