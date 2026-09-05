import Foundation

/// Search over the history: case- and diacritic-insensitive substring first,
/// then an in-order subsequence match for typo-tolerant "fuzzy" hits.
enum HistorySearch {
    struct Match: Equatable {
        /// Lower is better. Substring hits score below fuzzy hits.
        var score: Double
        /// Ranges in `title` to highlight (may be empty when the hit is only in the full text).
        var titleRanges: [Range<String.Index>]
    }

    static func match(query: String, title: String, searchText: String) -> Match? {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return Match(score: 0, titleRanges: []) }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        // 1. Every whitespace-separated term must appear somewhere (in title or full text).
        let terms = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        var ranges: [Range<String.Index>] = []
        var allTermsFound = true
        var bonus = 0.0
        for term in terms {
            if let range = title.range(of: term, options: options) {
                ranges.append(range)
                if range.lowerBound == title.startIndex { bonus -= 0.1 }
            } else if searchText.range(of: term, options: options) != nil {
                bonus += 0.2
            } else {
                allTermsFound = false
                break
            }
        }
        if allTermsFound {
            return Match(score: 1 + bonus + Double(title.count) / 100_000, titleRanges: mergeRanges(ranges))
        }

        // 2. Fuzzy: characters of the query appear in order in the title.
        guard needle.count >= 2 && needle.count <= 32 else { return nil }
        return subsequenceMatch(needle: needle, haystack: String(title.prefix(300)))
    }

    private static func subsequenceMatch(needle: String, haystack: String) -> Match? {
        let needleChars = Array(needle.lowercased())
        let haystackLower = haystack.lowercased()
        var ranges: [Range<String.Index>] = []
        var needleIndex = 0
        var gapPenalty = 0.0
        var lastMatchOffset = -1
        var offset = 0
        var index = haystackLower.startIndex
        while index < haystackLower.endIndex, needleIndex < needleChars.count {
            if haystackLower[index] == needleChars[needleIndex] {
                let next = haystackLower.index(after: index)
                ranges.append(index..<next)
                if lastMatchOffset >= 0 { gapPenalty += Double(offset - lastMatchOffset - 1) }
                lastMatchOffset = offset
                needleIndex += 1
            }
            index = haystackLower.index(after: index)
            offset += 1
        }
        guard needleIndex == needleChars.count else { return nil }
        // Convert to indices of the original string (lowercasing preserves counts for our purposes).
        let originalRanges = ranges.compactMap { range -> Range<String.Index>? in
            let start = haystackLower.distance(from: haystackLower.startIndex, to: range.lowerBound)
            guard let lower = haystack.index(haystack.startIndex, offsetBy: start, limitedBy: haystack.endIndex),
                  lower < haystack.endIndex else { return nil }
            return lower..<haystack.index(after: lower)
        }
        let score = 5 + gapPenalty / Double(max(haystack.count, 1)) * 10 + Double(gapPenalty) * 0.01
        return Match(score: score, titleRanges: mergeRanges(originalRanges))
    }

    static func mergeRanges(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
