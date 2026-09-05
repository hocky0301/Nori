import SwiftUI

/// "Pasting needs Accessibility access · Enable · ✕" — 28 pt, at most once a day.
struct AccessibilityBanner: View {
    let model: PanelModel

    @State private var closeHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.yellow)
            Text("Pasting needs Accessibility access")
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Button {
                model.actions.enablePasting()
            } label: {
                Text("Enable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            Spacer(minLength: 0)
            Button {
                model.showsAccessibilityBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(closeHovered ? 0.1 : 0), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { closeHovered = $0 }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
