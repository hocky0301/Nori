import SwiftUI

/// Placeholder panel UI until the designed views land: proves the pipeline end to end.
struct PanelRootView: View {
    @Bindable var model: PanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding([.horizontal, .top], 12)
            HStack {
                ForEach(PanelFilter.allCases) { chip in
                    Text(chip.label)
                        .font(.caption.weight(model.filter == chip ? .semibold : .regular))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(model.filter == chip ? Color.accentColor.opacity(0.25) : .clear, in: Capsule())
                        .onTapGesture { model.filter = chip }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.sections) { section in
                            Text(section.title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.top, 8)
                            ForEach(section.rows) { row in
                                HStack {
                                    Image(systemName: row.row.kind.symbolName).frame(width: 20)
                                    Text(row.row.displayTitle).lineLimit(2)
                                    Spacer()
                                    if let n = row.number { Text("⌘\(n)").foregroundStyle(.secondary).font(.caption) }
                                    if row.row.isPinned { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption2) }
                                }
                                .padding(8)
                                .background(model.selectedID == row.id ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                .id(row.id)
                                .onTapGesture { model.perform(.click, bits: ActionGrammar.Bits(modifierFlags: NSEvent.modifierFlags), on: row.id) }
                                .onHover { if $0 { model.hoverSelect(id: row.id) } }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: model.scrollRequest) {
                    if let id = model.selectedID { proxy.scrollTo(id) }
                }
            }
            HStack(spacing: 14) {
                ForEach(Array(model.hintChips.enumerated()), id: \.offset) { _, chip in
                    HStack(spacing: 4) {
                        Text(chip.key).font(.caption2.weight(.medium)).padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        Text(chip.verb).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 10)
            if let toast = model.toast {
                Text(toast).font(.caption).padding(6).background(.thinMaterial, in: Capsule())
            }
        }
        .frame(width: PanelPlacement.width)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onAppear { searchFocused = true }
        .onChange(of: model.isOpen) { _, open in if open { searchFocused = true } }
    }
}
