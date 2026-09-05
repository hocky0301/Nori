import AppKit
import Foundation
import Observation
import ServiceManagement

/// App-wide preferences. Observable so both AppKit controllers and SwiftUI settings
/// panes react to changes; every property persists to `UserDefaults` immediately.
///
/// Nothing here changes what a key does — see `ActionGrammar`.
@MainActor
@Observable
final class NoriSettings {
    /// Under XCTest the host app must never touch the user's real preferences.
    static let shared = NoriSettings(defaults: isRunningTests ? UserDefaults(suiteName: "io.github.hocky0301.Nori.tests")! : .standard)

    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    enum PanelPosition: String, CaseIterable, Identifiable, Sendable {
        case cursor, center, statusItem
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cursor: String(localized: "At the mouse pointer")
            case .center: String(localized: "Center of the screen")
            case .statusItem: String(localized: "Under the menu bar icon")
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }

        cycleModeEnabled = bool(Key.cycleModeEnabled, true)
        panelPosition = PanelPosition(rawValue: defaults.string(forKey: Key.panelPosition) ?? "") ?? .cursor
        showMenuBarIcon = bool(Key.showMenuBarIcon, true)
        captureText = bool(Key.captureText, true)
        captureImages = bool(Key.captureImages, true)
        captureFiles = bool(Key.captureFiles, true)
        maxItems = int(Key.maxItems, 500)
        expireAfterDays = int(Key.expireAfterDays, 0)
        maxImageMegabytes = int(Key.maxImageMegabytes, 10)
        captureUniversalClipboard = bool(Key.captureUniversalClipboard, true)
        ignoredTypes = defaults.stringArray(forKey: Key.ignoredTypes) ?? PasteboardType.defaultIgnoredTypes
        ignoreRegexps = defaults.stringArray(forKey: Key.ignoreRegexps) ?? []
        ignoredApps = defaults.stringArray(forKey: Key.ignoredApps) ?? PasteboardType.defaultIgnoredApps
        maskSensitive = bool(Key.maskSensitive, true)
        showGhostRows = bool(Key.showGhostRows, true)
        clearOnQuit = bool(Key.clearOnQuit, false)
        clearSystemClipboardOnClear = bool(Key.clearSystemClipboardOnClear, false)
        showAppIcons = bool(Key.showAppIcons, true)
        showKeycaps = bool(Key.showKeycaps, true)
        showHintBar = bool(Key.showHintBar, true)
        ocrImages = bool(Key.ocrImages, false)
        hasCompletedOnboarding = bool(Key.hasCompletedOnboarding, false)
        accessibilityGrantedOnce = bool(Key.accessibilityGrantedOnce, false)
        accessibilityBannerLastShownAt = defaults.object(forKey: Key.accessibilityBannerLastShownAt) as? Date
        pasteBlockedByAccessibility = bool(Key.pasteBlockedByAccessibility, false)
        pausedUntil = defaults.object(forKey: Key.pausedUntil) as? Date
        notSavedCount = int(Key.notSavedCount, 0)
        notSavedCountDay = defaults.string(forKey: Key.notSavedCountDay) ?? ""
        pollInterval = defaults.object(forKey: Key.pollInterval) as? Double ?? 0.2
    }

    enum Key {
        static let cycleModeEnabled = "cycleModeEnabled"
        static let panelPosition = "panelPosition"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let captureText = "captureText"
        static let captureImages = "captureImages"
        static let captureFiles = "captureFiles"
        static let maxItems = "maxItems"
        static let expireAfterDays = "expireAfterDays"
        static let maxImageMegabytes = "maxImageMegabytes"
        static let captureUniversalClipboard = "captureUniversalClipboard"
        static let ignoredTypes = "ignoredPasteboardTypes"
        static let ignoreRegexps = "ignoreRegexes"
        static let ignoredApps = "ignoredApps"
        static let maskSensitive = "maskSensitive"
        static let showGhostRows = "showGhostRows"
        static let clearOnQuit = "clearOnQuit"
        static let clearSystemClipboardOnClear = "clearSystemClipboardOnClear"
        static let showAppIcons = "showAppIcons"
        static let showKeycaps = "showKeycaps"
        static let showHintBar = "showHintBar"
        static let ocrImages = "ocrImages"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let accessibilityGrantedOnce = "accessibilityGrantedOnce"
        static let accessibilityBannerLastShownAt = "accessibilityBannerLastShownAt"
        static let pasteBlockedByAccessibility = "pasteBlockedByAccessibility"
        static let pausedUntil = "pauseUntil"
        static let notSavedCount = "notSavedCount"
        static let notSavedCountDay = "notSavedCountDay"
        static let pollInterval = "clipboardCheckInterval"
    }

    // General
    var cycleModeEnabled: Bool { didSet { defaults.set(cycleModeEnabled, forKey: Key.cycleModeEnabled) } }
    var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: Key.panelPosition) } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }

    // Capture
    var captureText: Bool { didSet { defaults.set(captureText, forKey: Key.captureText) } }
    var captureImages: Bool { didSet { defaults.set(captureImages, forKey: Key.captureImages) } }
    var captureFiles: Bool { didSet { defaults.set(captureFiles, forKey: Key.captureFiles) } }
    var maxItems: Int { didSet { defaults.set(maxItems, forKey: Key.maxItems) } }
    var expireAfterDays: Int { didSet { defaults.set(expireAfterDays, forKey: Key.expireAfterDays) } }
    var maxImageMegabytes: Int { didSet { defaults.set(maxImageMegabytes, forKey: Key.maxImageMegabytes) } }
    var captureUniversalClipboard: Bool { didSet { defaults.set(captureUniversalClipboard, forKey: Key.captureUniversalClipboard) } }
    var ignoredTypes: [String] { didSet { defaults.set(ignoredTypes, forKey: Key.ignoredTypes) } }
    var ignoreRegexps: [String] { didSet { defaults.set(ignoreRegexps, forKey: Key.ignoreRegexps) } }
    var ocrImages: Bool { didSet { defaults.set(ocrImages, forKey: Key.ocrImages) } }
    var pollInterval: Double { didSet { defaults.set(pollInterval, forKey: Key.pollInterval) } }

    // Privacy
    var ignoredApps: [String] { didSet { defaults.set(ignoredApps, forKey: Key.ignoredApps) } }
    var maskSensitive: Bool { didSet { defaults.set(maskSensitive, forKey: Key.maskSensitive) } }
    var showGhostRows: Bool { didSet { defaults.set(showGhostRows, forKey: Key.showGhostRows) } }
    var clearOnQuit: Bool { didSet { defaults.set(clearOnQuit, forKey: Key.clearOnQuit) } }
    var clearSystemClipboardOnClear: Bool { didSet { defaults.set(clearSystemClipboardOnClear, forKey: Key.clearSystemClipboardOnClear) } }

    // Look
    var showAppIcons: Bool { didSet { defaults.set(showAppIcons, forKey: Key.showAppIcons) } }
    var showKeycaps: Bool { didSet { defaults.set(showKeycaps, forKey: Key.showKeycaps) } }
    var showHintBar: Bool { didSet { defaults.set(showHintBar, forKey: Key.showHintBar) } }

    // Internal state
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }
    var accessibilityGrantedOnce: Bool { didSet { defaults.set(accessibilityGrantedOnce, forKey: Key.accessibilityGrantedOnce) } }
    var accessibilityBannerLastShownAt: Date? { didSet { defaults.set(accessibilityBannerLastShownAt, forKey: Key.accessibilityBannerLastShownAt) } }
    var pasteBlockedByAccessibility: Bool { didSet { defaults.set(pasteBlockedByAccessibility, forKey: Key.pasteBlockedByAccessibility) } }
    /// nil = capturing; `.distantFuture` = paused until resumed; otherwise resumes at that date.
    var pausedUntil: Date? { didSet { defaults.set(pausedUntil, forKey: Key.pausedUntil) } }
    var notSavedCount: Int { didSet { defaults.set(notSavedCount, forKey: Key.notSavedCount) } }
    var notSavedCountDay: String { didSet { defaults.set(notSavedCountDay, forKey: Key.notSavedCountDay) } }

    var capturePolicy: CapturePolicy {
        var policy = CapturePolicy()
        policy.ignoredTypes = Set(ignoredTypes)
        policy.ignoredApps = Set(ignoredApps)
        policy.ignoreRegexps = ignoreRegexps
        policy.captureText = captureText
        policy.captureImages = captureImages
        policy.captureFiles = captureFiles
        policy.captureUniversalClipboard = captureUniversalClipboard
        policy.maskSensitive = maskSensitive
        policy.maxImageBytes = maxImageMegabytes * 1024 * 1024
        return policy
    }

    /// "3 items not saved today" bookkeeping.
    func recordNotSaved(on date: Date = .now) {
        let day = Self.dayKey(date)
        if notSavedCountDay != day {
            notSavedCountDay = day
            notSavedCount = 0
        }
        notSavedCount += 1
    }

    func notSavedToday(now: Date = .now) -> Int {
        notSavedCountDay == Self.dayKey(now) ? notSavedCount : 0
    }

    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
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

    var launchAtLoginRequiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
