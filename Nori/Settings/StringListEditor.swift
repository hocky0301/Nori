import SwiftUI

/// An editable list of strings rendered as Form rows: a text field per entry with a remove
/// button, plus an add row. Used for ignored pasteboard types and ignore patterns.
struct StringListEditor: View {
    @Binding var items: [String]
    var placeholder: String
    /// Entries failing this are drawn in red but still saved (the capture policy skips them).
    var isValid: (String) -> Bool = { _ in true }
    var restoreDefaults: (() -> Void)? = nil
    var emptyText = String(localized: "Nothing yet")

    @FocusState private var focusedIndex: Int?

    var body: some View {
        if items.isEmpty {
            Text(emptyText)
                .foregroundStyle(.tertiary)
        }
        ForEach(items.indices, id: \.self) { index in
            HStack(spacing: 8) {
                TextField(placeholder, text: binding(at: index))
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .foregroundStyle(isValid(item(at: index)) ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                    .focused($focusedIndex, equals: index)
                if !isValid(item(at: index)) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help("This pattern doesn't compile, so it is ignored")
                }
                Button {
                    remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove")
            }
        }
        HStack(spacing: 12) {
            Button {
                items.append("")
                focusedIndex = items.count - 1
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            if let restoreDefaults {
                Button("Restore defaults", action: restoreDefaults)
                    .buttonStyle(.borderless)
            }
            Spacer()
        }
        .font(.callout)
    }

    private func item(at index: Int) -> String {
        items.indices.contains(index) ? items[index] : ""
    }

    /// Index-based rows can outlive a deletion for one render; guard against stale indices.
    private func binding(at index: Int) -> Binding<String> {
        Binding(
            get: { item(at: index) },
            set: { newValue in
                if items.indices.contains(index) { items[index] = newValue }
            }
        )
    }

    private func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        focusedIndex = nil
        items.remove(at: index)
    }
}
