import SwiftUI

/// PINNED / TODAY / YESTERDAY / EARLIER / RESULTS — 11 pt semibold, uppercase, tracking 0.4.
struct SectionHeader: View {
    let title: String
    var isFirst = false

    var body: some View {
        Text(title.uppercased())
            .font(.sectionHeader)
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, PanelMetrics.cardPadH)
            // LazyVStack spacing (4) already separates this from its neighbours.
            .padding(.top, isFirst ? 2 : PanelMetrics.sectionAbove - PanelMetrics.cardGap)
            .padding(.bottom, PanelMetrics.sectionBelow - PanelMetrics.cardGap)
            .accessibilityAddTraits(.isHeader)
    }
}
