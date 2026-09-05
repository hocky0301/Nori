import SwiftUI

/// "Deleted · ⌘Z to undo", "Copied", "Cleared 142 clips" — 4 s, bottom-center over the list.
struct Toast: View {
    let text: String

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Text(text)
            .font(.toast)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                    .overlay(Capsule().fill(theme.toastFill))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .allowsHitTesting(false)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
