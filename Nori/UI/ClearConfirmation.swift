import SwiftUI

/// Nori's own confirmation, inside the panel: Esc cancels, ↩ clears, ⌥ includes pinned.
struct ClearConfirmation: View {
    let model: PanelModel
    let count: Int
    let pinnedCount: Int

    @Environment(\.panelTheme) private var theme

    private var includePinned: Bool { model.modifierBits.contains(.keepOpen) }

    var body: some View {
        ZStack {
            Color.primary.opacity(0.04)
                .contentShape(Rectangle())
                .onTapGesture { model.isClearConfirmationVisible = false }
            VStack(spacing: 14) {
                Image(systemName: "trash")
                    .font(.system(size: 26, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    Text(includePinned ? "Clear history including pinned?" : "Clear clipboard history?")
                        .font(.emptyTitle)
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.emptyBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    FlatButton(title: "Cancel", key: "Esc", prominent: false) {
                        model.isClearConfirmationVisible = false
                    }
                    FlatButton(title: includePinned ? "Clear Including Pinned" : "Clear", key: "↩", prominent: true) {
                        model.clearHistory(includingPinned: includePinned)
                    }
                }
                .padding(.top, 2)
                if !includePinned, pinnedCount > 0 {
                    Text("Hold ⌥ to remove pinned clips too")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .frame(width: 340)
            .background(
                Color(nsColor: .windowBackgroundColor).opacity(0.92),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        }
        .animation(.easeInOut(duration: 0.1), value: includePinned)
    }

    private var message: String {
        let clips = count == 1 ? "1 clip" : "\(count) clips"
        if includePinned {
            let pinned = pinnedCount == 1 ? "1 pinned clip" : "\(pinnedCount) pinned clips"
            return "\(clips) and \(pinned) will be removed. This can't be undone."
        }
        return pinnedCount > 0
            ? "\(clips) will be removed. Pinned clips are kept."
            : "\(clips) will be removed. This can't be undone."
    }
}

/// A flat capsule button with its key printed inside; accent when prominent.
struct FlatButton: View {
    let title: String
    let key: String
    let prominent: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Keycap(text: key)
                    .opacity(prominent ? 0.9 : 1)
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 28)
            .background(
                prominent ? Color.accentColor.opacity(hovered ? 0.9 : 1) : Color.primary.opacity(hovered ? 0.12 : 0.08),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
    }
}
