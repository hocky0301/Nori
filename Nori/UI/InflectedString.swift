import Foundation

extension String {
    /// A localized string with `^[…](inflect: true)` grammar agreement applied — "1 clip", "3 clips".
    ///
    /// `String(localized:)` leaves the markup untouched; only the attributed initializer runs the
    /// inflection engine, so count strings go through here.
    init(inflected value: String.LocalizationValue) {
        self = String(AttributedString(localized: value).characters)
    }
}
