import Foundation

/// User-configurable rules that decide whether a pasteboard change is worth keeping.
struct CapturePolicy: Sendable, Equatable {
    /// Custom pasteboard types whose presence means "do not record this copy".
    var ignoredTypes: Set<String> = Set(PasteboardType.defaultIgnoredTypes)
    /// Bundle identifiers of apps whose copies are never recorded.
    var ignoredApps: Set<String> = []
    /// When true, `ignoredApps` becomes an allow-list instead.
    var recordOnlyListedApps = false
    /// Regular expressions; a plain-text item matching any of them is dropped.
    var ignoreRegexps: [String] = []
    var captureImages = true
    var captureFiles = true
    /// Keep RTF/HTML representations next to plain text.
    var captureRichText = true
    /// Single representations above this size are dropped (protects the database from huge TIFFs).
    var maxRepresentationBytes = 64 * 1024 * 1024

    static let `default` = CapturePolicy()
}

/// Why a pasteboard change was not recorded. Surfaced in logs and the debug menu.
enum CaptureRejection: Sendable, Equatable {
    case fromNori(UUID?)
    case privateOrTransient(String)
    case ignoredType(String)
    case ignoredApp(String)
    case matchedIgnoreRegexp
    case nothingToStore
}

enum CaptureOutcome: Sendable, Equatable {
    case captured(ClipDraft)
    case rejected(CaptureRejection)
}
