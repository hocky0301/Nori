import SwiftUI

/// All · Text · Links · Code · Colors · Images · Files — fixed order, layout never jumps.
struct FilterChips: View {
    let model: PanelModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelFilter.allCases) { filter in
                FilterChip(
                    label: filter.label,
                    isSelected: model.filter == filter,
                    isEmpty: model.count(for: filter) == 0
                ) {
                    model.filter = filter
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: PanelMetrics.chipHeight)
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let isEmpty: Bool
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.panelTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(isSelected ? .chipSelected : .chip)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(height: PanelMetrics.chipHeight)
                .background(fill, in: RoundedRectangle(cornerRadius: PanelMetrics.Radius.chip, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .opacity(isEmpty && !isSelected ? 0.35 : 1)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return .accentColor }
        return hovered ? theme.hover : .clear
    }
}
