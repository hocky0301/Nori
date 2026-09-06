import AppKit
import SwiftUI

/// One history item: summary row, optional inline preview, selection, hover, click and context menu.
struct ClipCard: View {
    let model: PanelModel
    let entry: PanelSections.Row

    @Environment(\.panelTheme) private var theme
    @Environment(\.panelMotion) private var motion

    private var row: ClipRow { entry.row }
    private var isSelected: Bool { model.selectedID == row.id }
    private var isExpanded: Bool { model.expandedID == row.id }

    var body: some View {
        Button {
            model.perform(.click, bits: ActionGrammar.Bits(modifierFlags: NSEvent.modifierFlags), on: row.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: PanelMetrics.metaGap) {
                    CardContent(row: row, titleRanges: entry.titleRanges, query: model.query)
                    CardMeta(model: model, row: row, number: entry.number)
                }
                if isExpanded {
                    ExpandedPreview(model: model, row: row)
                        .transition(motion.reduce ? .identity : .opacity.animation(.easeIn(duration: 0.12).delay(0.16)))
                }
            }
            .padding(.vertical, PanelMetrics.cardPadV)
            .padding(.horizontal, PanelMetrics.cardPadH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: PanelMetrics.Radius.card, style: .continuous))
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: PanelMetrics.Radius.card, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.Radius.card, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .focusable(false)
        .onHover { inside in
            if inside { model.hoverSelect(id: row.id) }
        }
        .contextMenu { CardContextMenu(model: model, row: row) }
        .animation(motion.expand, value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return theme.cardSelectedFill }
        if isExpanded { return theme.cardExpandedGround }
        return theme.cardGround
    }

    private var stroke: Color? {
        if isSelected { return theme.cardSelectedStroke }
        if isExpanded { return theme.cardExpandedStroke }
        return nil
    }
}

/// Pressed = scale 0.985 for 80 ms; nothing else.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Right-click: the chord for every action, from the same grammar the keys use.
struct CardContextMenu: View {
    let model: PanelModel
    let row: ClipRow

    private var caps: ActionGrammar.Capabilities { .init(accessibilityTrusted: model.accessibilityTrusted) }

    private func verb(_ bits: ActionGrammar.Bits) -> String {
        ActionGrammar.verb(for: ActionGrammar.resolve(.click, bits, caps))
    }

    /// "Paste    ↩" — the localized verb with its chord printed after it.
    private func item(_ verb: String, _ key: String) -> String {
        "\(verb)    \(key)"
    }

    var body: some View {
        Button(item(verb([]), "↩")) { model.perform(.click, bits: [], on: row.id) }
        Button(item(verb([.plain]), "⇧↩")) { model.perform(.click, bits: [.plain], on: row.id) }
        if !row.isSensitive {
            Button(item(verb([.keepOpen]), "⌥↩")) { model.perform(.click, bits: [.keepOpen], on: row.id) }
        }
        Button(item(String(localized: "Copy"), "⌘↩")) { model.perform(.click, bits: [.copyOnly], on: row.id) }
        if !row.isSensitive {
            Divider()
            Button(item(String(localized: "Preview"), String(localized: "Space"))) { model.select(id: row.id, scroll: false); model.toggleExpanded() }
            Button(item(row.isPinned ? String(localized: "Unpin") : String(localized: "Pin"), "⌘P")) { model.select(id: row.id, scroll: false); model.togglePinSelected() }
            switch row.kind {
            case .link:
                Divider()
                Button(item(String(localized: "Open in Browser"), "⌘O")) { model.actions.open(row) }
            case .file:
                Divider()
                Button(item(String(localized: "Open"), "⌘O")) { model.actions.open(row) }
                Button(item(String(localized: "Reveal in Finder"), "⌘R")) { model.actions.reveal(row) }
            case .image:
                Divider()
                Button(item(String(localized: "Open"), "⌘O")) { model.actions.open(row) }
            case .text, .code, .color:
                EmptyView()
            }
        }
        Divider()
        Button(item(String(localized: "Delete"), "⌘⌫")) { model.select(id: row.id, scroll: false); model.deleteSelected() }
    }
}
