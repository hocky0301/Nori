import SwiftUI

/// The printed key: 11 pt medium, 18 pt tall, r=5, min width 26.
struct Keycap: View {
    let text: String

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Text(text)
            .font(.keycap)
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: 26)
            .frame(height: 18)
            .background(theme.keycapFill, in: RoundedRectangle(cornerRadius: PanelMetrics.Radius.keycap, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PanelMetrics.Radius.keycap, style: .continuous)
                    .strokeBorder(theme.keycapStroke, lineWidth: 1)
            }
    }
}
