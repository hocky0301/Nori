import SwiftUI

/// The 28 pt bar: every chord that applies right now, re-rendered on each modifier change.
struct HintBar: View {
    let model: PanelModel

    @Environment(\.panelMotion) private var motion

    var body: some View {
        let chips = model.hintChips
        // Chips that don't fit are dropped from the right, never squeezed or clipped mid-glyph.
        ViewThatFits(in: .horizontal) {
            ForEach(0..<max(chips.count, 1), id: \.self) { drop in
                row(Array(chips.dropLast(drop)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PanelMetrics.hintBarHeight)
        .id(chips.map { $0.key + $0.verb }.joined(separator: "|"))
        .transition(.opacity)
        .animation(motion.hint, value: chips)
    }

    private func row(_ chips: [HintBarModel.Chip]) -> some View {
        HStack(spacing: PanelMetrics.hintGap) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                if chip.isWarning {
                    WarningHintChip(chip: chip) { model.actions.enablePasting() }
                } else {
                    HintChip(chip: chip)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

struct HintChip: View {
    let chip: HintBarModel.Chip

    var body: some View {
        HStack(spacing: 4) {
            Keycap(text: chip.key)
            Text(chip.verb)
                .font(.hint)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// `↩ Copy · Enable pasting →` — the whole chip opens the Accessibility pane.
struct WarningHintChip: View {
    let chip: HintBarModel.Chip
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
                Keycap(text: chip.key)
                Text(chip.verb)
                    .font(.hint)
                    .foregroundStyle(hovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .underline(hovered)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .help("Open System Settings › Privacy & Security › Accessibility")
    }
}
