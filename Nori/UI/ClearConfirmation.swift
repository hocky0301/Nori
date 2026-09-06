import SwiftUI

/// Nori's own confirmation, inside the panel: Esc cancels, ↩ clears, ⌥ includes pinned.
struct ClearConfirmation: View {
    let model: PanelModel
    /// Unpinned persisted clips.
    let count: Int
    let pinnedCount: Int
    /// Masked secrets in the vault; clearing removes them too, so they count.
    let sensitiveCount: Int

    init(model: PanelModel, count: Int, pinnedCount: Int, sensitiveCount: Int = 0) {
        self.model = model
        self.count = count
        self.pinnedCount = pinnedCount
        self.sensitiveCount = sensitiveCount
    }

    @Environment(\.panelTheme) private var theme

    private var includePinned: Bool { model.modifierBits.contains(.keepOpen) }

    /// How many rows disappear on Clear: unpinned clips, masked secrets, and pinned clips while ⌥ is held.
    static func removedCount(count: Int, pinnedCount: Int, sensitiveCount: Int, includePinned: Bool) -> Int {
        count + sensitiveCount + (includePinned ? pinnedCount : 0)
    }

    private var removedCount: Int {
        Self.removedCount(count: count, pinnedCount: pinnedCount, sensitiveCount: sensitiveCount, includePinned: includePinned)
    }

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
                    FlatButton(title: "Cancel", key: String(localized: "Esc"), prominent: false) {
                        model.isClearConfirmationVisible = false
                    }
                    FlatButton(title: includePinned ? "Clear Including Pinned" : "Clear", key: "↩", prominent: true) {
                        model.clearHistory(includingPinned: includePinned)
                    }
                    .disabled(removedCount == 0)
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
        Self.message(count: count, pinnedCount: pinnedCount, sensitiveCount: sensitiveCount, includePinned: includePinned)
    }

    /// "3 clips will be removed. Pinned clips are kept." — secrets count as clips; "1 clip" stays singular.
    static func message(count: Int, pinnedCount: Int, sensitiveCount: Int, includePinned: Bool) -> String {
        let clips = count + sensitiveCount
        if includePinned {
            return String(inflected: "^[\(clips) clip](inflect: true) and ^[\(pinnedCount) pinned clip](inflect: true) will be removed. This can't be undone.")
        }
        return pinnedCount > 0
            ? String(inflected: "^[\(clips) clip](inflect: true) will be removed. Pinned clips are kept.")
            : String(inflected: "^[\(clips) clip](inflect: true) will be removed. This can't be undone.")
    }
}

/// A flat capsule button with its key printed inside; accent when prominent; dimmed when disabled.
struct FlatButton: View {
    let title: LocalizedStringKey
    let key: String
    let prominent: Bool
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

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
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
    }
}
