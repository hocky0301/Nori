import AppKit
import SwiftUI

/// The panel (§2.1): search row, filter chips, the list, a hairline and the hint bar,
/// on the one glass surface. 560 wide; the height is fixed per open by the controller.
struct PanelRootView: View {
    @Bindable var model: PanelModel
    @FocusState private var searchFocused: Bool

    @Environment(\.panelTheme) private var theme
    @Environment(\.panelMotion) private var motion

    var body: some View {
        VStack(spacing: 0) {
            SearchRow(model: model, focus: $searchFocused)
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.top, PanelMetrics.inset)

            FilterChips(model: model)
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.top, PanelMetrics.rowGap)

            if model.showsAccessibilityBanner {
                AccessibilityBanner(model: model)
                    .padding(.horizontal, PanelMetrics.inset)
                    .padding(.top, PanelMetrics.rowGap)
                    .transition(.opacity)
            }

            ClipList(model: model)
                .padding(.top, PanelMetrics.rowGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        Toast(text: toast)
                            .padding(.bottom, 10)
                            .transition(motion.toastTransition)
                    }
                }
                .overlay {
                    if model.isClearConfirmationVisible {
                        ClearConfirmation(
                            model: model,
                            count: model.history.count - model.history.pinnedCount,
                            pinnedCount: model.history.pinnedCount
                        )
                        .transition(.opacity)
                    }
                }
                .animation(model.toast == nil ? motion.toastOut : motion.toastIn, value: model.toast)
                .animation(.easeInOut(duration: 0.12), value: model.isClearConfirmationVisible)

            if model.settings.showHintBar {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.5))
                    .frame(height: 1)
                    .padding(.top, PanelMetrics.rowGap)
                HintBar(model: model)
                    .padding(.horizontal, PanelMetrics.inset)
            } else {
                Spacer().frame(height: PanelMetrics.rowGap)
            }

            Spacer().frame(height: PanelMetrics.inset)
        }
        .frame(width: PanelPlacement.width)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: PanelMetrics.Radius.panel))
        .animation(.easeInOut(duration: 0.12), value: model.showsAccessibilityBanner)
        .onAppear { searchFocused = true }
        .onChange(of: model.isOpen) { _, open in
            if open {
                focusSearch()
            } else {
                searchFocused = false
                PreviewImageCache.shared.removeAll()
            }
        }
        // Clicking a preview's text view steals first responder; any keyboard navigation hands it back.
        .onChange(of: model.scrollRequest) { focusSearch() }
        .onChange(of: model.filter) { focusSearch() }
        .onChange(of: model.isClearConfirmationVisible) { _, visible in
            if !visible { focusSearch() }
        }
    }

    private func focusSearch() {
        guard model.isOpen else { return }
        searchFocused = true
        // The panel becomes key right after `isOpen` flips; assert focus again once it has.
        Task { @MainActor in
            searchFocused = true
        }
    }
}

/// Scroll position bookkeeping the list needs without re-rendering on every frame.
@MainActor
final class ListGeometry {
    var cardFrames: [UUID: CGRect] = [:]
    var contentOffsetY: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var visibleMaxY: CGFloat { contentOffsetY + viewportHeight }
}

/// Sections in a `LazyVStack`; keeps the selection visible and scrolls an expanding card up when needed.
struct ClipList: View {
    let model: PanelModel

    @State private var geometry = ListGeometry()
    @Environment(\.panelMotion) private var motion

    var body: some View {
        if model.historyIsEmpty, model.ghosts.isEmpty {
            EmptyState(kind: .noHistory(hotkey: model.hotkeyDisplay))
        } else if model.isEmpty {
            if model.isSearching {
                EmptyState(kind: .noMatches(query: model.query.trimmingCharacters(in: .whitespaces)))
            } else {
                EmptyState(kind: .filterEmpty(model.filter))
            }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: PanelMetrics.cardGap) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                        SectionHeader(title: section.title, isFirst: index == 0)
                        ForEach(section.rows) { entry in
                            rowView(entry)
                                .id(entry.id)
                                .transition(motion.rowTransition)
                        }
                    }
                }
                .padding(.horizontal, PanelMetrics.inset)
                .padding(.bottom, 4)
                .coordinateSpace(.named("list"))
                .animation(motion.rows, value: model.sections)
            }
            .scrollIndicators(.automatic)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                geometry.contentOffsetY = offset
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                geometry.viewportHeight = height
            }
            .onChange(of: model.scrollRequest) {
                scrollToSelection(proxy)
            }
            .onAppear {
                scrollToSelection(proxy)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ entry: PanelSections.Row) -> some View {
        if entry.row.isGhost {
            GhostRow(reason: entry.row.ghostReason ?? entry.row.title)
        } else {
            ClipCard(model: model, entry: entry)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("list")) } action: { frame in
                    geometry.cardFrames[entry.id] = frame
                }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = model.selectedID else { return }
        if model.expandedID == id, let frame = geometry.cardFrames[id] {
            // Expanding: only scroll when the grown card would fall below the visible list.
            let projectedBottom = frame.minY + PanelMetrics.expandedCardMaxHeight
            if geometry.viewportHeight > 0, projectedBottom > geometry.visibleMaxY {
                withAnimation(motion.expand) { proxy.scrollTo(id, anchor: .top) }
            }
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { proxy.scrollTo(id) }
    }
}
