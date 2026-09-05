import Foundation

/// User-configurable rules that decide whether a pasteboard change is worth keeping.
struct CapturePolicy: Sendable, Equatable {
    /// Custom pasteboard types whose presence means "do not record this copy".
    var ignoredTypes: Set<String> = Set(PasteboardType.defaultIgnoredTypes)
    /// Bundle identifiers of apps whose copies are never recorded.
    var ignoredApps: Set<String> = Set(PasteboardType.defaultIgnoredApps)
    /// Regular expressions; a plain-text item matching any of them is dropped.
    var ignoreRegexps: [String] = []
    var captureText = true
    var captureImages = true
    var captureFiles = true
    var captureUniversalClipboard = true
    /// Detect secrets and keep them in memory only (masked).
    var maskSensitive = true
    /// Images above this size are not stored (a ghost row explains why).
    var maxImageBytes = 10 * 1024 * 1024
    /// Plain text above this size is truncated (and RTF/HTML dropped).
    var maxTextBytes = 2 * 1024 * 1024
    /// Any other single representation above this size is dropped from the clip.
    var maxOtherRepresentationBytes = 1 * 1024 * 1024

    static let `default` = CapturePolicy()
}

/// Why a pasteboard change was not recorded.
enum CaptureRejection: Sendable, Equatable {
    case fromNori(UUID?)
    case ephemeral(String)
    case ignoredType(String)
    case ignoredApp(String)
    case universalClipboardDisabled
    case matchedIgnoreRegexp
    case nothingToStore
}

/// A copy that was deliberately not kept, but should leave a visible trace.
enum GhostReason: Sendable, Equatable {
    case concealed(appName: String?)
    case imageTooLarge(bytes: Int)

    var message: String {
        switch self {
        case let .concealed(appName):
            "Concealed item from \(appName ?? "an app") wasn't saved"
        case let .imageTooLarge(bytes):
            "Image too large (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))) wasn't saved"
        }
    }
}

/// Secret-looking text: kept in memory only, masked, and forgotten after a while.
struct SensitiveDraft: Sendable, Equatable {
    var match: SecretDetector.Match
    var mask: String
    var draft: ClipDraft
}

enum CaptureOutcome: Sendable, Equatable {
    case captured(ClipDraft)
    case sensitive(SensitiveDraft)
    case ghost(GhostReason)
    case rejected(CaptureRejection)
}
