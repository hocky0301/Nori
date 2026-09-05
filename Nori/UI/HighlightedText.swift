import SwiftUI

/// Search highlights: an accent tint behind every matched run, never bold (bold jitters the list).
enum HighlightedText {
    static func attributed(_ text: String, query: String, highlight: Color) -> AttributedString {
        var result = AttributedString(text)
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return result }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for term in terms {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: options, range: searchRange) {
                if let lower = AttributedString.Index(found.lowerBound, within: result),
                   let upper = AttributedString.Index(found.upperBound, within: result) {
                    result[lower..<upper].backgroundColor = highlight
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return result
    }
}

/// `Text` that tints matched runs when a query is active.
struct MatchText: View {
    let text: String
    let query: String

    @Environment(\.panelTheme) private var theme

    var body: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(text)
        } else {
            Text(HighlightedText.attributed(text, query: query, highlight: theme.matchHighlight))
        }
    }
}
