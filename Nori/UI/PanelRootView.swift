import SwiftUI

/// Placeholder panel UI until the design spec lands: proves the pipeline end to end.
struct PanelRootView: View {
    @Bindable var model: PanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search history", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding([.horizontal, .top], 12)
            ScrollViewReader { proxy in
                List(model.rows, selection: $model.selectedID) { row in
                    HStack {
                        Image(systemName: row.item.kind.symbolName)
                        Text(row.item.title).lineLimit(2)
                        Spacer()
                        if let n = model.quickNumber(for: row) { Text("⌘\(n)").foregroundStyle(.secondary) }
                    }
                    .tag(row.id)
                    .id(row.id)
                }
                .onChange(of: model.scrollRequest) {
                    if let id = model.selectedID { proxy.scrollTo(id) }
                }
            }
            Text("\(model.rows.count) items · ↩ paste · ⌥↩ copy · ⌘⌫ delete")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .onAppear { searchFocused = true }
        .onChange(of: model.isOpen) { _, open in if open { searchFocused = true } }
    }
}
