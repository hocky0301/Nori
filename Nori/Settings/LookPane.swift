import SwiftUI

/// Settings › Look (§8): three toggles. Nothing here changes what a key does.
struct LookPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Toggle("Show app icons on clips", isOn: $settings.showAppIcons)
                Toggle("Show ⌘1–⌘9 on clips", isOn: $settings.showKeycaps)
                Toggle("Show keyboard hints at the bottom of the panel", isOn: $settings.showHintBar)
            } footer: {
                Text("The panel follows the system appearance and accent color.")
            }
        }
        .formStyle(.grouped)
    }
}
