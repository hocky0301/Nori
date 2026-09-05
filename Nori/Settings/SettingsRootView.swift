import SwiftUI

/// Placeholder until the designed settings panes land.
struct SettingsRootView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Text("\(tab.title) (placeholder)")
                    .frame(width: 520, height: 400)
                    .tabItem { Label(tab.title, systemImage: tab.symbolName) }
                    .tag(tab)
            }
        }
        .frame(width: 520)
    }
}
