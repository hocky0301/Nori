import SwiftUI

/// "Concealed item from 1Password wasn't saved": a content-free, unselectable 32 pt row.
struct GhostRow: View {
    let reason: String

    var body: some View {
        Text(reason)
            .font(.ghost)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.ghostHeight)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: PanelMetrics.Radius.ghost, style: .continuous)
                        .fill(.tertiary.opacity(0.5))
                    Stripes()
                        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.Radius.ghost, style: .continuous))
                }
            }
            .accessibilityLabel("Not saved: \(reason)")
    }
}

/// 45° 2 pt stripes at `primary.opacity(0.05)`.
struct Stripes: View {
    var spacing: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(.primary.opacity(0.06)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}
