import Carbon.HIToolbox
import Foundation
import Testing
@testable import Nori

/// `KeyCodeLookup` must find the key that types "v" on the ⌘ layer of the *current* layout.
/// The tests never switch the user's input source; other layouts are only enumerated.
@Suite("KeyCodeLookup")
struct KeyCodeLookupTests {
    /// Read-only view of the current keyboard layout, independent of the code under test.
    enum Layout {
        static var id: String {
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
            return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }

        /// Translate a virtual key through the current layout, like the OS would for a key press.
        static func translate(_ code: CGKeyCode, withCommand: Bool) -> String? {
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            let modifiers: UInt32 = withCommand ? UInt32((cmdKey >> 8) & 0xFF) : 0
            return layoutData.withUnsafeBytes { raw -> String? in
                guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                var deadKeyState: UInt32 = 0
                var buffer = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, buffer.count, &length, &buffer
                )
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: buffer, count: length)
            }
        }

        /// Whether any of the 128 virtual keys types "v" on this layout (plain or ⌘ layer).
        static var hasV: Bool {
            (0..<128).contains { code in
                translate(CGKeyCode(code), withCommand: true)?.lowercased() == "v"
                    || translate(CGKeyCode(code), withCommand: false)?.lowercased() == "v"
            }
        }

        static var hasPlainV: Bool {
            (0..<128).contains { translate(CGKeyCode($0), withCommand: false)?.lowercased() == "v" }
        }

        static let usLike = ["com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.USExtended", "com.apple.keylayout.British"]
    }

    @Test(.enabled(if: Layout.hasV, "the current layout has no v key"))
    func commandVTranslatesToVOnTheCommandLayer() throws {
        let code = KeyCodeLookup.commandV()
        let typed = try #require(Layout.translate(code, withCommand: true), "layout \(Layout.id), code \(code)")
        #expect(typed.lowercased() == "v")
        #expect(KeyCodeLookup.keyCode(for: "v", withCommand: true) != nil, "layout \(Layout.id)")
    }

    @Test(.enabled(if: Layout.hasPlainV, "the current layout has no plain v key"))
    func plainLookupMatchesTheUnmodifiedLayer() throws {
        let code = try #require(KeyCodeLookup.keyCode(for: "v"))
        #expect(Layout.translate(code, withCommand: false)?.lowercased() == "v")
        // Upper-case input resolves to the same key.
        #expect(KeyCodeLookup.keyCode(for: "V") == code)
    }

    @Test func fallbackIsANSIV() {
        #expect(CGKeyCode(kVK_ANSI_V) == 9)
    }

    @Test(.enabled(if: Layout.usLike.contains(Layout.id), "only meaningful on US-style layouts"))
    func usStyleLayoutsResolveToANSIV() {
        #expect(KeyCodeLookup.commandV() == 9, "on \(Layout.id) the v key is the ANSI V key")
        #expect(KeyCodeLookup.keyCode(for: "v", withCommand: true) == 9)
    }

    @Test func charactersAbsentFromTheLayoutAreNil() {
        // U+1F600 is on no keyboard layout; a non-nil answer would mean the scan is wrong.
        #expect(KeyCodeLookup.keyCode(for: "😀") == nil)
        #expect(KeyCodeLookup.keyCode(for: "😀", withCommand: true) == nil)
    }

    @Test func installedLayoutsAreEnumerableWithoutSwitching() {
        let before = Layout.id
        let all = (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
        let layoutIDs: [String] = all.compactMap { source in
            guard let typePointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType),
                  Unmanaged<CFString>.fromOpaque(typePointer).takeUnretainedValue() as String == kTISTypeKeyboardLayout as String,
                  let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
        }
        let interesting = layoutIDs.filter { id in
            ["Dvorak", "Japanese", "French", "Colemak", "German"].contains { id.localizedCaseInsensitiveContains($0) }
        }
        #expect(!layoutIDs.isEmpty, "macOS always ships at least one keyboard layout")
        // Only the current layout is exercised: switching the user's input source is off limits.
        if Layout.hasV {
            #expect(KeyCodeLookup.keyCode(for: "v", withCommand: true) != nil, "current layout \(before); others present: \(interesting)")
        }
        #expect(Layout.id == before)
    }
}
