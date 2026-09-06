import SwiftUI

/// Search highlights: an accent tint behind every matched run, never bold (bold jitters the list).
///
/// The runs come from `HistorySearch` (via `PanelSections.Row.titleRanges`), so fuzzy hits light up
/// exactly the characters that matched. Cards show a transformed title (first line, whitespace
/// collapsed, tabs expanded…), so the helpers below rebuild that display string while carrying the
/// ranges over instead of searching the displayed text again.
enum HighlightedText {
    /// A display string with the source indices each character came from.
    struct Mapped: Equatable {
        var text: String
        /// Ranges in `text` to highlight.
        var ranges: [Range<String.Index>]
    }

    static func attributed(_ text: String, ranges: [Range<String.Index>], highlight: Color) -> AttributedString {
        var result = AttributedString(text)
        for range in ranges {
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result), lower < upper {
                result[lower..<upper].backgroundColor = highlight
            }
        }
        return result
    }

    static func attributed(_ text: String, query: String, highlight: Color) -> AttributedString {
        attributed(text, ranges: queryRanges(in: text, query: query), highlight: highlight)
    }

    /// Substring search over the displayed text — the fallback when a display string cannot be
    /// mapped back onto the title (a normalized color, a percent-decoded link path, an image caption).
    static func queryRanges(in text: String, query: String) -> [Range<String.Index>] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var ranges: [Range<String.Index>] = []
        for term in terms {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: options, range: searchRange) {
                ranges.append(found)
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return HistorySearch.mergeRanges(ranges)
    }

    // MARK: Title transforms (must stay in step with `ClipRow`)

    /// `ClipRow.displayTitle` — first non-empty line, whitespace runs collapsed — with `ranges` carried over.
    static func displayTitle(_ title: String, ranges: [Range<String.Index>]) -> Mapped {
        var builder = Builder(source: title, ranges: ranges)
        guard let lineStart = title.firstIndex(where: { !$0.isNewline }) else {
            return builder.finish()
        }
        let lineEnd = title[lineStart...].firstIndex(where: \.isNewline) ?? title.endIndex
        var pendingSpace: String.Index?
        var index = lineStart
        while index < lineEnd {
            let character = title[index]
            if character.isWhitespace {
                if !builder.isEmpty, pendingSpace == nil { pendingSpace = index }
            } else {
                if let space = pendingSpace {
                    builder.append(" ", from: space)
                    pendingSpace = nil
                }
                builder.append(character, from: index)
            }
            index = title.index(after: index)
        }
        return builder.finish()
    }

    /// `ClipRow.codeLines` joined by newlines — tabs as four spaces, leading blank lines skipped,
    /// two lines at most — with `ranges` carried over.
    static func codeLines(_ title: String, ranges: [Range<String.Index>]) -> Mapped {
        var lines: [[(Character, String.Index)]] = [[]]
        for index in title.indices {
            let character = title[index]
            if character.isNewline {
                lines.append([])
            } else if character == "\t" {
                lines[lines.count - 1].append(contentsOf: repeatElement((" ", index), count: 4))
            } else {
                lines[lines.count - 1].append((character, index))
            }
        }
        let firstNonEmpty = lines.firstIndex { line in
            !String(line.map(\.0)).trimmingCharacters(in: .whitespaces).isEmpty
        } ?? 0
        var builder = Builder(source: title, ranges: ranges)
        for (offset, line) in lines[firstNonEmpty...].prefix(2).enumerated() {
            if offset > 0 { builder.append("\n", from: nil) }
            for (character, index) in line { builder.append(character, from: index) }
        }
        return builder.finish()
    }

    /// `display`, when it occurs verbatim inside `title` (a file name, a link host), with the
    /// `ranges` that fall inside that occurrence; nil when it does not occur.
    static func substring(_ display: String, of title: String, ranges: [Range<String.Index>]) -> Mapped? {
        guard !display.isEmpty, let found = title.range(of: display) else { return nil }
        var builder = Builder(source: title, ranges: ranges)
        for index in title[found].indices { builder.append(title[index], from: index) }
        return builder.finish()
    }

    /// Appends characters while remembering which source index each came from, then turns the
    /// source ranges into ranges over the built string.
    private struct Builder {
        let source: String
        let ranges: [Range<String.Index>]
        private var text = ""
        private var highlighted: [Bool] = []

        init(source: String, ranges: [Range<String.Index>]) {
            self.source = source
            self.ranges = ranges
        }

        var isEmpty: Bool { text.isEmpty }

        mutating func append(_ character: Character, from index: String.Index?) {
            text.append(character)
            highlighted.append(index.map { source in ranges.contains { $0.contains(source) } } ?? false)
        }

        func finish() -> Mapped {
            var result: [Range<String.Index>] = []
            var runStart: String.Index?
            for (index, flag) in zip(text.indices, highlighted) {
                if flag, runStart == nil { runStart = index }
                if !flag, let start = runStart {
                    result.append(start..<index)
                    runStart = nil
                }
            }
            if let start = runStart { result.append(start..<text.endIndex) }
            return Mapped(text: text, ranges: result)
        }
    }
}

/// `Text` that tints the matched runs of a display string.
struct MatchText: View {
    let mapped: HighlightedText.Mapped

    @Environment(\.panelTheme) private var theme

    init(_ mapped: HighlightedText.Mapped) {
        self.mapped = mapped
    }

    var body: some View {
        if mapped.ranges.isEmpty {
            Text(mapped.text)
        } else {
            Text(HighlightedText.attributed(mapped.text, ranges: mapped.ranges, highlight: theme.matchHighlight))
        }
    }
}
