import Foundation

extension String {
    /// A localized string with grammar agreement applied. `String(localized:)` leaves the
    /// `^[…](inflect: true)` markup untouched; plural agreement runs on the Markdown-aware path.
    init(inflected value: String.LocalizationValue) {
        self = String(AttributedString(localized: value).characters)
    }
}
