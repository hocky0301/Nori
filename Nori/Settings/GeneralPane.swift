import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Settings › General: hotkey, cycling, login item, panel position, menu bar icon, pasting status, appearance.
struct GeneralPane: View {
    @Bindable var model: SettingsModel
    @State private var launchAtLogin = false
    @State private var launchAtLoginRequiresApproval = false
    @State private var isTrusted = Paster.isTrusted

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Nori", name: .togglePanel)
                Toggle("Hold the modifiers and tap the key again to step through clips", isOn: $settings.cycleModeEnabled)
            }
            Section {
                loginItemRow
                Picker("Show the panel", selection: $settings.panelPosition) {
                    ForEach(NoriSettings.PanelPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                Toggle(isOn: $settings.showMenuBarIcon) {
                    Text("Show icon in the menu bar")
                    Text("Without it, open Settings with ⌘, inside the panel")
                }
            }
            Section {
                Toggle("Show app icons on clips", isOn: $settings.showAppIcons)
                Toggle("Show keyboard hints at the bottom of the panel", isOn: $settings.showHintBar)
            } footer: {
                Text("The panel follows the system appearance and accent color.")
            }
            Section {
                pastingRow
                LabeledContent("Welcome") {
                    Button("Show welcome again") { model.showOnboarding() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLoginItem)
        .onChange(of: launchAtLogin) { _, wanted in
            guard wanted != model.settings.launchAtLogin else { return }
            model.settings.launchAtLogin = wanted
            refreshLoginItem()
        }
        .task(id: model.isWindowVisible) {
            // Trust drifts after rebuilds and updates; re-read it while the window is on screen.
            guard model.isWindowVisible else { return }
            while !Task.isCancelled {
                isTrusted = Paster.isTrusted
                refreshLoginItem()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var loginItemRow: some View {
        if launchAtLoginRequiresApproval {
            Toggle(isOn: .constant(true)) {
                Text("Start Nori when I log in")
                Text("Enabled in System Settings — approve Nori under General › Login Items.")
            }
            .disabled(true)
            LabeledContent("") {
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
        } else {
            Toggle("Start Nori when I log in", isOn: $launchAtLogin)
        }
    }

    private var pastingRow: some View {
        LabeledContent("Pasting") {
            if isTrusted {
                Label("Enabled", systemImage: "checkmark")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                HStack(spacing: 8) {
                    Text("Not enabled —")
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") { model.coordinator.enablePasting() }
                }
            }
        }
    }

    private func refreshLoginItem() {
        launchAtLoginRequiresApproval = model.settings.launchAtLoginRequiresApproval
        let actual = model.settings.launchAtLogin
        if launchAtLogin != actual { launchAtLogin = actual }
    }
}
