import SwiftUI

struct SettingsRootView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Group {
                    switch tab {
                    case .general: Text("General (placeholder)")
                    case .appearance: Text("Appearance (placeholder)")
                    case .privacy: Text("Privacy (placeholder)")
                    case .storage: Text("Storage (placeholder)")
                    case .about: Text("About (placeholder)")
                    }
                }
                .tabItem { Label(tab.title, systemImage: tab.symbolName) }
                .tag(tab)
            }
        }
        .frame(width: 620, height: 480)
    }
}
