import Foundation
import Testing
@testable import Nori

/// Every default from spec §8, read from an empty suite, plus persistence and the not-saved counter.
@Suite("NoriSettingsDefaults")
@MainActor
struct NoriSettingsDefaultsTests {
    /// A throw-away defaults suite that is wiped when the test ends.
    @MainActor
    final class DefaultsSuite {
        let name = "tests-\(UUID().uuidString)"
        var defaults: UserDefaults { UserDefaults(suiteName: name)! }
        func settings() -> NoriSettings { NoriSettings(defaults: defaults) }
        deinit { UserDefaults.standard.removePersistentDomain(forName: name) }
    }

    @Test func generalDefaults() {
        let settings = DefaultsSuite().settings()
        #expect(settings.cycleModeEnabled == true)
        #expect(settings.panelPosition == .cursor)
        #expect(settings.showMenuBarIcon == true)
    }

    @Test func captureDefaults() {
        let settings = DefaultsSuite().settings()
        #expect(settings.captureText == true)
        #expect(settings.captureImages == true)
        #expect(settings.captureFiles == true)
        #expect(settings.maxItems == 500)
        #expect(settings.expireAfterDays == 0, "Never")
        #expect(settings.maxImageMegabytes == 10)
        #expect(settings.captureUniversalClipboard == true)
        #expect(settings.ignoredTypes == PasteboardType.defaultIgnoredTypes)
        #expect(settings.ignoredTypes.contains("com.agilebits.onepassword"))
        #expect(settings.ignoreRegexps.isEmpty)
        #expect(settings.pollInterval == 0.2)
        #expect(settings.ocrImages == false, "OCR is v1.5 and off by default")
    }

    @Test func privacyDefaults() {
        let settings = DefaultsSuite().settings()
        #expect(settings.ignoredApps == PasteboardType.defaultIgnoredApps)
        #expect(settings.ignoredApps.contains("com.1password.1password"))
        #expect(settings.maskSensitive == true)
        #expect(settings.showGhostRows == true)
        #expect(settings.clearOnQuit == false)
        #expect(settings.clearSystemClipboardOnClear == false)
    }

    @Test func lookDefaults() {
        let settings = DefaultsSuite().settings()
        #expect(settings.showAppIcons == true)
        #expect(settings.showKeycaps == true)
        #expect(settings.showHintBar == true)
    }

    @Test func internalStateDefaults() {
        let settings = DefaultsSuite().settings()
        #expect(settings.hasCompletedOnboarding == false)
        #expect(settings.accessibilityGrantedOnce == false)
        #expect(settings.accessibilityBannerLastShownAt == nil)
        #expect(settings.pasteBlockedByAccessibility == false)
        #expect(settings.pausedUntil == nil)
        #expect(settings.notSavedCount == 0)
        #expect(settings.notSavedCountDay == "")
        #expect(settings.notSavedToday() == 0)
    }

    @Test func keysMatchTheSpec() {
        #expect(NoriSettings.Key.cycleModeEnabled == "cycleModeEnabled")
        #expect(NoriSettings.Key.panelPosition == "panelPosition")
        #expect(NoriSettings.Key.showMenuBarIcon == "showMenuBarIcon")
        #expect(NoriSettings.Key.maxItems == "maxItems")
        #expect(NoriSettings.Key.expireAfterDays == "expireAfterDays")
        #expect(NoriSettings.Key.maxImageMegabytes == "maxImageMegabytes")
        #expect(NoriSettings.Key.captureUniversalClipboard == "captureUniversalClipboard")
        #expect(NoriSettings.Key.ignoredTypes == "ignoredPasteboardTypes")
        #expect(NoriSettings.Key.ignoreRegexps == "ignoreRegexes")
        #expect(NoriSettings.Key.ignoredApps == "ignoredApps")
        #expect(NoriSettings.Key.maskSensitive == "maskSensitive")
        #expect(NoriSettings.Key.showGhostRows == "showGhostRows")
        #expect(NoriSettings.Key.clearOnQuit == "clearOnQuit")
        #expect(NoriSettings.Key.clearSystemClipboardOnClear == "clearSystemClipboardOnClear")
        #expect(NoriSettings.Key.showAppIcons == "showAppIcons")
        #expect(NoriSettings.Key.showKeycaps == "showKeycaps")
        #expect(NoriSettings.Key.showHintBar == "showHintBar")
        #expect(NoriSettings.Key.hasCompletedOnboarding == "hasCompletedOnboarding")
        #expect(NoriSettings.Key.pausedUntil == "pauseUntil")
        #expect(NoriSettings.Key.notSavedCount == "notSavedCount")
        #expect(NoriSettings.Key.notSavedCountDay == "notSavedCountDay")
    }

    @Test func changesPersistAndReloadThroughTheSameSuite() {
        let suite = DefaultsSuite()
        let settings = suite.settings()
        settings.cycleModeEnabled = false
        settings.panelPosition = .statusItem
        settings.maxItems = 1_200
        settings.expireAfterDays = 7
        settings.ignoreRegexps = ["^order-[0-9]+$"]
        settings.ignoredApps.append("com.example.vault")
        settings.pausedUntil = .distantFuture
        settings.accessibilityBannerLastShownAt = Date(timeIntervalSince1970: 1_800_000_000)
        settings.showHintBar = false

        // Written immediately, under the §8 key names.
        #expect(suite.defaults.bool(forKey: "cycleModeEnabled") == false)
        #expect(suite.defaults.string(forKey: "panelPosition") == "statusItem")
        #expect(suite.defaults.integer(forKey: "maxItems") == 1_200)
        #expect(suite.defaults.stringArray(forKey: "ignoreRegexes") == ["^order-[0-9]+$"])

        let reloaded = suite.settings()
        #expect(reloaded.cycleModeEnabled == false)
        #expect(reloaded.panelPosition == .statusItem)
        #expect(reloaded.maxItems == 1_200)
        #expect(reloaded.expireAfterDays == 7)
        #expect(reloaded.ignoreRegexps == ["^order-[0-9]+$"])
        #expect(reloaded.ignoredApps.last == "com.example.vault")
        #expect(reloaded.pausedUntil == .distantFuture)
        #expect(reloaded.accessibilityBannerLastShownAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reloaded.showHintBar == false)

        // Clearing a date key returns it to nil, not to a stale value.
        settings.pausedUntil = nil
        #expect(suite.settings().pausedUntil == nil)
    }

    @Test func unknownPanelPositionFallsBackToCursor() {
        let suite = DefaultsSuite()
        suite.defaults.set("underTheCaret", forKey: NoriSettings.Key.panelPosition)
        #expect(suite.settings().panelPosition == .cursor)
    }

    @Test func notSavedCounterRollsOverAtMidnight() {
        let settings = DefaultsSuite().settings()
        var day = DateComponents()
        day.year = 2026; day.month = 9; day.day = 5; day.hour = 10
        let morning = Calendar.current.date(from: day)!
        let evening = morning.addingTimeInterval(11 * 3_600)
        let tomorrow = morning.addingTimeInterval(24 * 3_600)

        settings.recordNotSaved(on: morning)
        settings.recordNotSaved(on: evening)
        #expect(settings.notSavedCount == 2)
        #expect(settings.notSavedToday(now: evening) == 2)
        #expect(settings.notSavedToday(now: tomorrow) == 0, "yesterday's count is not today's")
        #expect(settings.notSavedToday(now: morning.addingTimeInterval(-86_400)) == 0)

        settings.recordNotSaved(on: tomorrow)
        #expect(settings.notSavedCount == 1, "a new day restarts the counter")
        #expect(settings.notSavedToday(now: tomorrow) == 1)
        #expect(settings.notSavedToday(now: evening) == 0)
        #expect(settings.notSavedCountDay == "2026-9-6")
    }

    @Test func capturePolicyMirrorsTheSettings() {
        let settings = DefaultsSuite().settings()
        #expect(settings.capturePolicy == CapturePolicy.default, "defaults produce the default policy")

        settings.captureText = false
        settings.captureImages = false
        settings.captureFiles = false
        settings.captureUniversalClipboard = false
        settings.maskSensitive = false
        settings.maxImageMegabytes = 25
        settings.ignoredTypes = ["com.example.type"]
        settings.ignoredApps = ["com.example.app"]
        settings.ignoreRegexps = ["a+", "b+"]

        let policy = settings.capturePolicy
        #expect(policy.captureText == false)
        #expect(policy.captureImages == false)
        #expect(policy.captureFiles == false)
        #expect(policy.captureUniversalClipboard == false)
        #expect(policy.maskSensitive == false)
        #expect(policy.maxImageBytes == 25 * 1024 * 1024)
        #expect(policy.ignoredTypes == ["com.example.type"])
        #expect(policy.ignoredApps == ["com.example.app"])
        #expect(policy.ignoreRegexps == ["a+", "b+"])
        #expect(policy.maxTextBytes == CapturePolicy.default.maxTextBytes, "not user-configurable")
    }

    @Test func panelPositionLabels() {
        #expect(NoriSettings.PanelPosition.allCases.map(\.rawValue) == ["cursor", "center", "statusItem"])
        #expect(NoriSettings.PanelPosition.cursor.label == "At the mouse pointer")
    }
}
