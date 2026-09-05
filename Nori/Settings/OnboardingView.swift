import KeyboardShortcuts
import SwiftUI

/// The three-step welcome (§7): hotkey → Accessibility → login item. 520 × 440, page dots,
/// Back/Continue at the bottom; Continue (or Done) is the default button.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let coordinator: AppCoordinator
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 1: HotkeyStep(model: model)
                case 2: AccessibilityStep(model: model, coordinator: coordinator)
                default: LoginItemStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 44)  // clears the (hidden-title) traffic lights
            footer
        }
        .frame(width: OnboardingWindowController.size.width, height: OnboardingWindowController.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: model.isVisible) {
            // Temporary listener: shows "That's it" when the chord is pressed. Ends with the window.
            guard model.isVisible else { return }
            for await event in KeyboardShortcuts.events(for: .togglePanel) where event == .keyDown {
                model.shortcutPressed = true
            }
        }
        .task(id: model.isVisible) {
            guard model.isVisible else { return }
            while !Task.isCancelled {
                let trusted = Paster.isTrusted
                if trusted != model.accessibilityTrusted {
                    model.accessibilityTrusted = trusted
                    if trusted { coordinator.settings.accessibilityGrantedOnce = true }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") { model.back() }
                .opacity(model.isFirstStep ? 0 : 1)
                .disabled(model.isFirstStep)
            Spacer()
            PageDots(count: OnboardingModel.stepCount, current: model.step)
            Spacer()
            if model.isLastStep {
                Button("Done", action: finish)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { model.next() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 12)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...count, id: \.self) { index in
                Circle()
                    .fill(index == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Step \(current) of \(count)")
    }
}

private struct StepTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 1

private struct HotkeyStep: View {
    @Bindable var model: OnboardingModel
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)

    private static let alternatives: [(label: String, shortcut: KeyboardShortcuts.Shortcut)] = [
        ("⌘⇧C", .init(.c, modifiers: [.command, .shift])),
        ("⌃⌥V", .init(.v, modifiers: [.control, .option])),
    ]

    var body: some View {
        VStack(spacing: 14) {
            StepTitle(text: "Nori keeps what you copy")
            Text("Press this anywhere to open your clipboard history.")
                .foregroundStyle(.secondary)

            KeyboardShortcuts.Recorder(for: .togglePanel) { shortcut = $0 }
                .controlSize(.large)
                .padding(.top, 4)

            Group {
                if model.shortcutPressed {
                    Label("That's it — this opens Nori anywhere", systemImage: "checkmark")
                        .foregroundStyle(.green)
                } else {
                    Text("Try it now.")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout.weight(.medium))
            .frame(height: 20)

            VStack(spacing: 10) {
                Text("In Chrome and Slack, ⌘⇧V is 'paste and match style' — use ⇧↩ inside Nori instead, or pick ⌘⇧C")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ForEach(Self.alternatives, id: \.label) { option in
                        Button(option.label) {
                            KeyboardShortcuts.setShortcut(option.shortcut, for: .togglePanel)
                            shortcut = option.shortcut
                            model.shortcutPressed = false
                        }
                        .font(.body.monospaced())
                    }
                }
                if let shortcut, let typed = SettingsSupport.typedCharacter(for: shortcut) {
                    Label("This shortcut types “\(typed)”, so it won't work in password fields", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Step 2

private struct AccessibilityStep: View {
    @Bindable var model: OnboardingModel
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 14) {
            StepTitle(text: "Let Nori paste for you")
            Text("When you pick a clip, Nori presses ⌘V in the app you were using. macOS calls this permission Accessibility. Nori has no network access and stores clips only on this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Open System Settings") { coordinator.enablePasting() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.accessibilityTrusted)
                statusPill
            }
            .padding(.top, 6)

            VStack(spacing: 6) {
                Button("Skip for now") { model.next() }
                    .buttonStyle(.link)
                Text("Without it, ↩ copies the clip instead of pasting. You can turn this on later in Settings › General.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        }
    }

    private var statusPill: some View {
        Group {
            if model.accessibilityTrusted {
                Label("Enabled", systemImage: "checkmark")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.green, in: Capsule())
            } else {
                Text("Not enabled")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .font(.callout.weight(.medium))
        .animation(.default, value: model.accessibilityTrusted)
    }
}

// MARK: - Step 3

private struct LoginItemStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 14) {
            StepTitle(text: "Start at login?")
            Text("Nori lives in the menu bar and only needs to be running to remember what you copy.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Start Nori when I log in", isOn: $model.startAtLogin)
                .toggleStyle(.switch)
                .padding(14)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 6)

            Text("You can change this any time in Settings › General.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
