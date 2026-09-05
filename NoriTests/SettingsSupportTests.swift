import KeyboardShortcuts
import Testing
@testable import Nori

@Suite("SettingsSupport")
struct SettingsSupportTests {
    @Test func storageSummaryReadsLikeTheSpec() {
        #expect(SettingsSupport.storageSummary(bytes: 12_400_000, count: 342, pinned: 3) == "12.4 MB · 342 clips · 3 pinned")
        #expect(SettingsSupport.storageSummary(bytes: 0, count: 1, pinned: 0) == "0 bytes · 1 clip · 0 pinned")
    }

    @Test func regexValidity() {
        #expect(SettingsSupport.isValidRegex("^sk-[A-Za-z0-9]{20,}$"))
        #expect(SettingsSupport.isValidRegex(""))
        #expect(!SettingsSupport.isValidRegex("[unclosed"))
        #expect(!SettingsSupport.isValidRegex("(?<bad"))
    }

    @Test func commandAndControlChordsNeverTypeACharacter() {
        #expect(SettingsSupport.typedCharacter(for: .init(.v, modifiers: [.command, .shift])) == nil)
        #expect(SettingsSupport.typedCharacter(for: .init(.c, modifiers: [.command, .shift])) == nil)
        #expect(SettingsSupport.typedCharacter(for: .init(.v, modifiers: [.control, .option])) == nil)
    }

    @Test func bareLetterTypesACharacter() {
        // Any keyboard layout maps a letter key without modifiers to a printable character.
        let typed = SettingsSupport.typedCharacter(for: .init(.v, modifiers: []))
        #expect(typed?.isEmpty == false)
    }
}

@Suite("OnboardingModel")
@MainActor
struct OnboardingModelTests {
    @Test func stepsStayWithinRange() {
        let model = OnboardingModel()
        #expect(model.step == 1)
        #expect(model.isFirstStep)
        model.back()
        #expect(model.step == 1)
        model.next()
        model.next()
        #expect(model.step == 3)
        #expect(model.isLastStep)
        model.next()
        #expect(model.step == 3)
        model.go(to: 99)
        #expect(model.step == 3)
        model.go(to: -4)
        #expect(model.step == 1)
    }
}
