import AppKit
import SwiftUI

/// The 36 pt pill at the top: magnifier, the always-focused field, pause indicator and the ⋯ menu.
struct SearchRow: View {
    @Bindable var model: PanelModel
    var focus: FocusState<Bool>.Binding

    @Environment(\.panelTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            ZStack(alignment: .leading) {
                if model.query.isEmpty {
                    placeholder
                        .font(.search)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.search)
                    .focused(focus)
                    .autocorrectionDisabled()
            }

            if model.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .transition(.opacity)
            }

            PanelMenu(model: model)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: PanelMetrics.searchHeight)
        .background(theme.searchPill, in: RoundedRectangle(cornerRadius: PanelMetrics.Radius.search, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: model.isPaused)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let until = model.pausedUntil {
            if until == .distantFuture {
                Text("Capture paused")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Capture paused · \(Self.countdown(until: until, now: context.date))")
                        .monospacedDigit()
                }
            }
        } else {
            Text("Search")
        }
    }

    static func countdown(until: Date, now: Date) -> String {
        let remaining = max(Int(until.timeIntervalSince(now).rounded(.up)), 0)
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
}

/// The trailing `ellipsis.circle` menu.
struct PanelMenu: View {
    let model: PanelModel
    @State private var hovered = false

    var body: some View {
        Menu {
            if model.isPaused {
                Button("Resume Capture") { model.actions.resumeCapture() }
            } else {
                Menu("Pause Capture") {
                    Button("For 5 Minutes") { model.actions.pauseCapture(.now.addingTimeInterval(5 * 60)) }
                    Button("For 30 Minutes") { model.actions.pauseCapture(.now.addingTimeInterval(30 * 60)) }
                    Button("Until I Resume") { model.actions.pauseCapture(.distantFuture) }
                }
            }
            Button("Skip Next Copy") { model.actions.skipNextCopy() }
            Divider()
            Button("Clear History…") { model.showClearConfirmation() }
            Divider()
            Button("Settings…") { model.actions.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("About Nori") { model.actions.openAbout() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .opacity(hovered ? 1 : 0.5)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .accessibilityLabel("More")
    }
}
