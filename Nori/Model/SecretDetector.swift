import Foundation

/// High-precision detection of secrets that must never touch disk: private keys, cloud and
/// API tokens, JWTs and card numbers. Deliberately no entropy heuristics — git SHAs, UUIDs and
/// base64 blobs are everyday clipboard content and must not be hidden.
enum SecretDetector {
    enum Match: String, Sendable, CaseIterable {
        case privateKey, awsAccessKey, gitHubToken, gitHubFineGrainedToken, openAIKey, slackToken, googleAPIKey, jwt, cardNumber
    }

    private static let patterns: [(Match, NSRegularExpression)] = [
        (.privateKey, try! NSRegularExpression(pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#)),
        (.awsAccessKey, try! NSRegularExpression(pattern: #"\bAKIA[0-9A-Z]{16}\b"#)),
        (.gitHubToken, try! NSRegularExpression(pattern: #"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b"#)),
        (.gitHubFineGrainedToken, try! NSRegularExpression(pattern: #"\bgithub_pat_[A-Za-z0-9_]{22,}\b"#)),
        (.openAIKey, try! NSRegularExpression(pattern: #"\bsk-[A-Za-z0-9_-]{32,}\b"#)),
        (.slackToken, try! NSRegularExpression(pattern: #"\bxox[abpr]-[A-Za-z0-9-]{10,}\b"#)),
        (.googleAPIKey, try! NSRegularExpression(pattern: #"\bAIza[0-9A-Za-z_-]{35}\b"#)),
        (.jwt, try! NSRegularExpression(pattern: #"^eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}$"#)),
    ]

    /// Scans the whole text (up to the capture cap of a few MB — a copied `.env` or CI config is
    /// exactly where keys hide); the patterns are anchored and cheap.
    static func detect(in text: String) -> Match? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for (match, regex) in patterns where regex.firstMatch(in: trimmed, range: range) != nil {
            return match
        }
        if isCardNumber(trimmed) { return .cardNumber }
        return nil
    }

    /// 13–19 digits (spaces or dashes allowed) that pass Luhn.
    static func isCardNumber(_ text: String) -> Bool {
        guard text.count <= 25, text.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) else { return false }
        let digits = text.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count), digits.count == text.filter(\.isNumber).count else { return false }
        return luhnValid(digits)
    }

    static func luhnValid(_ digits: [Int]) -> Bool {
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// Everything but the last four characters becomes `•`, grouped in fours.
    static func mask(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.filter { !$0.isWhitespace && $0 != "-" }
        let visible = String(compact.suffix(4))
        let hiddenCount = min(max(compact.count - 4, 4), 16)
        var groups: [String] = []
        var remaining = hiddenCount
        while remaining > 0 {
            let take = min(4, remaining)
            groups.append(String(repeating: "•", count: take))
            remaining -= take
        }
        return (groups + [visible]).joined(separator: " ")
    }

    static func label(for match: Match) -> String {
        switch match {
        case .privateKey: String(localized: "Private key")
        case .awsAccessKey: String(localized: "AWS access key")
        case .gitHubToken, .gitHubFineGrainedToken: String(localized: "GitHub token")
        case .openAIKey: String(localized: "API key")
        case .slackToken: String(localized: "Slack token")
        case .googleAPIKey: String(localized: "Google API key")
        case .jwt: String(localized: "Access token")
        case .cardNumber: String(localized: "Card number")
        }
    }
}
