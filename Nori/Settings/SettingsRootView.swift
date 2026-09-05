import SwiftUI

/// One settings pane. The window controller hosts one of these per toolbar tab.
struct SettingsRootView: View {
    static let width: CGFloat = 520

    @Bindable var model: SettingsModel
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralPane(model: model)
            case .capture: CapturePane(model: model)
            case .privacy: PrivacyPane(model: model)
            case .look: LookPane(model: model)
            case .about: AboutPane()
            }
        }
        .frame(width: Self.width)
    }
}
