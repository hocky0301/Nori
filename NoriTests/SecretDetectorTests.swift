import Testing
@testable import Nori

@Suite("SecretDetector")
struct SecretDetectorTests {
    @Test("positives", arguments: [
        ("-----BEGIN RSA PRIVATE KEY-----\nMIIEow...", SecretDetector.Match.privateKey),
        ("-----BEGIN PRIVATE KEY-----", .privateKey),
        ("AKIAIOSFODNN7EXAMPLE", .awsAccessKey),
        ("token ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD here", .gitHubToken),
        ("github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz", .gitHubFineGrainedToken),
        ("sk-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF", .openAIKey),
        ("xoxb-1234567890-abcdefghij", .slackToken),
        ("AIzaSyD-abcdefghijklmnopqrstuvwxyz01234", .googleAPIKey),
        ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c", .jwt),
        ("4111 1111 1111 1111", .cardNumber),
        ("4242-4242-4242-4242", .cardNumber),
        ("378282246310005", .cardNumber),
    ])
    func detects(_ pair: (String, SecretDetector.Match)) {
        #expect(SecretDetector.detect(in: pair.0) == pair.1)
    }

    @Test("negatives", arguments: [
        "4111 1111 1111 1112",                      // fails Luhn
        "1234567890123",                            // fails Luhn
        "9780134685991",                            // ISBN-13 (Luhn fails)
        "3f786850e387550fdab836ed7e6dc881de23001b", // git SHA
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", // SHA-256
        "550e8400-e29b-41d4-a716-446655440000",     // UUID
        "SGVsbG8gd29ybGQsIHRoaXMgaXMgYSBiYXNlNjQgc3RyaW5nIQ==", // base64
        "https://example.com/path?token=abc",
        "sk-short",
        "AKIA1234",                                 // too short
        "ghp_short",
        "eyJhbGciOiJIUzI1NiJ9.only-two-parts",
        "The meeting is at 4111 Main Street, room 1111.",
        "brew install --cask nori",
        "12 34 56 78 90 12 34 5",                   // 15 digits, Luhn fails
        "0000 0000 0000 0000 0000",                 // 20 digits: too long
    ])
    func ignores(_ text: String) {
        #expect(SecretDetector.detect(in: text) == nil, Comment(rawValue: text))
    }

    @Test func longTextsAreScannedInFull() {
        let padding = String(repeating: "lorem ipsum dolor sit amet\n", count: 2_000)
        #expect(padding.utf16.count > 20_000)
        #expect(SecretDetector.detect(in: padding + "token ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD") == .gitHubToken)
        #expect(SecretDetector.detect(in: "-----BEGIN PRIVATE KEY-----\n" + padding) == .privateKey)
        #expect(SecretDetector.detect(in: padding) == nil)
    }

    @Test func masking() {
        #expect(SecretDetector.mask("4111 1111 1111 1111") == "•••• •••• •••• 1111")
        #expect(SecretDetector.mask("AKIAIOSFODNN7EXAMPLE") == "•••• •••• •••• •••• MPLE")
        let masked = SecretDetector.mask("ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD")
        #expect(masked.hasSuffix("ABCD"))
        #expect(!masked.contains("ghp"))
    }

    @Test func luhn() {
        #expect(SecretDetector.luhnValid([4, 5, 3, 9, 1, 4, 8, 8, 0, 3, 4, 3, 6, 4, 6, 7]))
        #expect(!SecretDetector.luhnValid([4, 5, 3, 9, 1, 4, 8, 8, 0, 3, 4, 3, 6, 4, 6, 8]))
    }
}
