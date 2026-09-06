import SwiftUI

/// Centered in the list area; the panel height never changes (§3.7).
struct EmptyState: View {
    enum Kind {
        case noHistory(hotkey: String)
        /// `pastes` is false when Accessibility is not trusted and ↩ can only copy the typed text.
        case noMatches(query: String, pastes: Bool)
        case filterEmpty(PanelFilter)
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: 8) {
            switch kind {
            case let .noHistory(hotkey):
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 44, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                Text("Nothing copied yet")
                    .font(.emptyTitle)
                    .foregroundStyle(.primary)
                Text("Copy something in any app — it shows up here.")
                    .font(.emptyBody)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Keycap(text: hotkey)
                    Text("opens Nori")
                        .font(.hint)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)

            case let .noMatches(query, pastes):
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text("No matches for “\(query)”")
                    .font(.emptyTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Keycap(text: "↩")
                    Group {
                        if pastes {
                            Text("pastes “\(query)” as text")
                        } else {
                            Text("copies “\(query)” as text")
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Text("·").foregroundStyle(.tertiary)
                    Keycap(text: "⌃U")
                    Text("clears")
                }
                .font(.hint)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            case let .filterEmpty(filter):
                Image(systemName: filter.symbolName)
                    .font(.system(size: 32, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text(filter.emptyMessage)
                    .font(.emptyTitle)
                    .foregroundStyle(.primary)
                Text("Copy \(Self.noun(for: filter)) in any app — it shows up here.")
                    .font(.emptyBody)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private static func noun(for filter: PanelFilter) -> String {
        switch filter {
        case .all: String(localized: "something")
        case .text: String(localized: "some text")
        case .link: String(localized: "a link")
        case .code: String(localized: "some code")
        case .color: String(localized: "a color value")
        case .image: String(localized: "an image")
        case .file: String(localized: "a file")
        }
    }
}
