import AppKit
import SwiftUI

/// The fixed 128 pt right column: app icon · relative time · ⌘n keycap · ★.
struct CardMeta: View {
    let model: PanelModel
    let row: ClipRow
    let number: Int?

    @Environment(\.panelMotion) private var motion

    var body: some View {
        HStack(spacing: PanelMetrics.metaGap) {
            if model.settings.showAppIcons {
                appIcon
            }
            Text(PanelSections.relativeTime(row.lastCopiedAt))
                .font(.meta)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let number, model.settings.showKeycaps {
                Keycap(text: "⌘\(number)")
                    .opacity(model.modifierBits.contains(.copyOnly) ? 1 : 0.5)
                    .animation(motion.keycap, value: model.modifierBits)
            }
            if row.isPinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Pinned")
            }
        }
        .frame(width: PanelMetrics.metaWidth, alignment: .trailing)
    }

    @ViewBuilder
    private var appIcon: some View {
        if row.isFromUniversalClipboard {
            Image(systemName: "iphone")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .help("Copied on another device")
        } else if let bundleID = row.sourceBundleID, let icon = AppIconCache.shared.appIcon(bundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .help(row.sourceAppName ?? bundleID)
        }
    }
}
