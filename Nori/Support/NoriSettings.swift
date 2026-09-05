import AppKit
import Foundation
import Observation
import ServiceManagement

/// App-wide preferences. Observable so both AppKit controllers and SwiftUI settings
/// panes react to changes; every property persists to `UserDefaults` immediately.
@MainActor
@Observable
final class NoriSettings {
    static let shared = NoriSettings()

    enum PanelPosition: String, CaseIterable, Identifiable, Sendable {
        case cursor, center, statusItem, activeWindow, lastPosition
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cursor: "At the mouse pointer"
            case .center: "Center of the screen"
            case .statusItem: "Below the menu bar icon"
            case .activeWindow: "Center of the active window"
            case .lastPosition: "Where I last left it"
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pasteOnSelect = defaults.object(forKey: Key.pasteOnSelect) as? Bool ?? true
        plainTextByDefault = defaults.bool(forKey: Key.plainTextByDefault)
        panelPosition = PanelPosition(rawValue: defaults.string(forKey: Key.panelPosition) ?? "") ?? .cursor
        panelWidth = defaults.object(forKey: Key.panelWidth) as? Double ?? 560
        panelHeight = defaults.object(forKey: Key.panelHeight) as? Double ?? 620
        lastPanelOrigin = defaults.string(forKey: Key.lastPanelOrigin).flatMap(NSPointFromString)
        maxItems = defaults.object(forKey: Key.maxItems) as? Int ?? 500
        pollInterval = defaults.object(forKey: Key.pollInterval) as? Double ?? 0.25
        showSourceAppIcons = defaults.object(forKey: Key.showSourceAppIcons) as? Bool ?? true
        showPreviewPane = defaults.object(forKey: Key.showPreviewPane) as? Bool ?? true
        captureImages = defaults.object(forKey: Key.captureImages) as? Bool ?? true
        captureFiles = defaults.object(forKey: Key.captureFiles) as? Bool ?? true
        captureRichText = defaults.object(forKey: Key.captureRichText) as? Bool ?? true
        ignoredApps = defaults.stringArray(forKey: Key.ignoredApps) ?? []
        recordOnlyListedApps = defaults.bool(forKey: Key.recordOnlyListedApps)
        ignoredTypes = defaults.stringArray(forKey: Key.ignoredTypes) ?? PasteboardType.defaultIgnoredTypes
        ignoreRegexps = defaults.stringArray(forKey: Key.ignoreRegexps) ?? []
        isPaused = defaults.bool(forKey: Key.isPaused)
        clearOnQuit = defaults.bool(forKey: Key.clearOnQuit)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        playSounds = defaults.bool(forKey: Key.playSounds)
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        ocrImages = defaults.object(forKey: Key.ocrImages) as? Bool ?? true
    }

    enum Key {
        static let pasteOnSelect = "pasteOnSelect"
        static let plainTextByDefault = "plainTextByDefault"
        static let panelPosition = "panelPosition"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let lastPanelOrigin = "lastPanelOrigin"
        static let maxItems = "maxItems"
        static let pollInterval = "pollInterval"
        static let showSourceAppIcons = "showSourceAppIcons"
        static let showPreviewPane = "showPreviewPane"
        static let captureImages = "captureImages"
        static let captureFiles = "captureFiles"
        static let captureRichText = "captureRichText"
        static let ignoredApps = "ignoredApps"
        static let recordOnlyListedApps = "recordOnlyListedApps"
        static let ignoredTypes = "ignoredTypes"
        static let ignoreRegexps = "ignoreRegexps"
        static let isPaused = "isPaused"
        static let clearOnQuit = "clearOnQuit"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let playSounds = "playSounds"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let ocrImages = "ocrImages"
    }

    /// Enter pastes into the active app (needs Accessibility). Off: Enter only copies.
    var pasteOnSelect: Bool { didSet { defaults.set(pasteOnSelect, forKey: Key.pasteOnSelect) } }
    var plainTextByDefault: Bool { didSet { defaults.set(plainTextByDefault, forKey: Key.plainTextByDefault) } }
    var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: Key.panelPosition) } }
    var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: Key.panelWidth) } }
    var panelHeight: Double { didSet { defaults.set(panelHeight, forKey: Key.panelHeight) } }
    var lastPanelOrigin: NSPoint? {
        didSet { defaults.set(lastPanelOrigin.map(NSStringFromPoint), forKey: Key.lastPanelOrigin) }
    }
    var maxItems: Int { didSet { defaults.set(maxItems, forKey: Key.maxItems) } }
    var pollInterval: Double { didSet { defaults.set(pollInterval, forKey: Key.pollInterval) } }
    var showSourceAppIcons: Bool { didSet { defaults.set(showSourceAppIcons, forKey: Key.showSourceAppIcons) } }
    var showPreviewPane: Bool { didSet { defaults.set(showPreviewPane, forKey: Key.showPreviewPane) } }
    var captureImages: Bool { didSet { defaults.set(captureImages, forKey: Key.captureImages) } }
    var captureFiles: Bool { didSet { defaults.set(captureFiles, forKey: Key.captureFiles) } }
    var captureRichText: Bool { didSet { defaults.set(captureRichText, forKey: Key.captureRichText) } }
    var ignoredApps: [String] { didSet { defaults.set(ignoredApps, forKey: Key.ignoredApps) } }
    var recordOnlyListedApps: Bool { didSet { defaults.set(recordOnlyListedApps, forKey: Key.recordOnlyListedApps) } }
    var ignoredTypes: [String] { didSet { defaults.set(ignoredTypes, forKey: Key.ignoredTypes) } }
    var ignoreRegexps: [String] { didSet { defaults.set(ignoreRegexps, forKey: Key.ignoreRegexps) } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.isPaused) } }
    var clearOnQuit: Bool { didSet { defaults.set(clearOnQuit, forKey: Key.clearOnQuit) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: Key.playSounds) } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    var ocrImages: Bool { didSet { defaults.set(ocrImages, forKey: Key.ocrImages) } }

    var panelSize: NSSize {
        get { NSSize(width: panelWidth, height: panelHeight) }
        set { panelWidth = newValue.width; panelHeight = newValue.height }
    }

    var capturePolicy: CapturePolicy {
        var policy = CapturePolicy()
        policy.ignoredTypes = Set(ignoredTypes)
        policy.ignoredApps = Set(ignoredApps)
        policy.recordOnlyListedApps = recordOnlyListedApps
        policy.ignoreRegexps = ignoreRegexps
        policy.captureImages = captureImages
        policy.captureFiles = captureFiles
        policy.captureRichText = captureRichText
        return policy
    }

    // MARK: Launch at login (SMAppService owns the truth; no key needed)

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login change failed: \(error)")
            }
        }
    }
}
