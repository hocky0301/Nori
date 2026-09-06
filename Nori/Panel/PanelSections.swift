import Foundation

/// Groups rows into PINNED / TODAY / YESTERDAY / EARLIER (or RESULTS while searching) and
/// assigns the positional ⌘1–9 numbers.
enum PanelSections {
    struct Section: Identifiable, Equatable, Sendable {
        var title: String
        var rows: [Row]
        var id: String { title }
    }

    struct Row: Identifiable, Equatable, Sendable {
        var row: ClipRow
        /// Highlight ranges in `row.title` for the current query.
        var titleRanges: [Range<String.Index>]
        /// ⌘1–9, positional over the visible list; nil past nine or for ghost rows.
        var number: Int?
        var id: UUID { row.id }
    }

    static func build(
        history: [ClipRow],
        sensitive: [ClipRow],
        ghosts: [ClipRow],
        filter: PanelFilter,
        query: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Section] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty

        var scored: [(Row, Double)] = []
        for row in history + sensitive where filter.matches(kind: row.kind) {
            if row.isSensitive, searching { continue }  // secrets are never indexed
            guard let match = HistorySearch.match(query: query, title: row.title, searchText: row.searchText) else { continue }
            // Fuzzy (subsequence) hits rank last and are not highlighted: scattered letters read as noise.
            let ranges = match.score >= 5 ? [] : match.titleRanges
            scored.append((Row(row: row, titleRanges: ranges, number: nil), match.score))
        }

        var sections: [Section] = []
        if searching {
            let ordered = scored.enumerated()
                .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
                .map(\.element.0)
            if !ordered.isEmpty { sections.append(Section(title: String(localized: "Results"), rows: ordered)) }
        } else {
            let pinned = scored.map(\.0).filter { $0.row.isPinned }
                .sorted { ($0.row.pinnedAt ?? .distantPast) < ($1.row.pinnedAt ?? .distantPast) }
            let unpinned = scored.map(\.0).filter { !$0.row.isPinned }
                .sorted { $0.row.lastCopiedAt > $1.row.lastCopiedAt }

            if !pinned.isEmpty { sections.append(Section(title: String(localized: "Pinned"), rows: pinned)) }

            let ghostRows = filter == .all ? ghosts.map { Row(row: $0, titleRanges: [], number: nil) } : []
            var today: [Row] = ghostRows
            var yesterday: [Row] = []
            var earlier: [Row] = []
            for row in unpinned {
                if calendar.isDate(row.row.lastCopiedAt, inSameDayAs: now) {
                    today.append(row)
                } else if let dayBefore = calendar.date(byAdding: .day, value: -1, to: now),
                          calendar.isDate(row.row.lastCopiedAt, inSameDayAs: dayBefore) {
                    yesterday.append(row)
                } else {
                    earlier.append(row)
                }
            }
            if !today.isEmpty { sections.append(Section(title: String(localized: "Today"), rows: today)) }
            if !yesterday.isEmpty { sections.append(Section(title: String(localized: "Yesterday"), rows: yesterday)) }
            if !earlier.isEmpty { sections.append(Section(title: String(localized: "Earlier"), rows: earlier)) }
        }

        // Numbers are positional over the visible list; ghost rows are skipped.
        var number = 1
        for sectionIndex in sections.indices {
            for rowIndex in sections[sectionIndex].rows.indices where number <= 9 {
                guard !sections[sectionIndex].rows[rowIndex].row.isGhost else { continue }
                sections[sectionIndex].rows[rowIndex].number = number
                number += 1
            }
        }
        return sections
    }

    /// Relative time for the meta column: "now", "2m", "1h", "1d", "Sep 3".
    static func relativeTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "now") }
        if seconds < 3_600 { let minutes = Int(seconds / 60); return String(localized: "\(minutes)m") }
        if seconds < 86_400 { let hours = Int(seconds / 3_600); return String(localized: "\(hours)h") }
        if seconds < 7 * 86_400 { let days = Int(seconds / 86_400); return String(localized: "\(days)d") }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d yyyy")
        return formatter.string(from: date)
    }
}
