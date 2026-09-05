import Foundation

/// Heuristics that decide whether a piece of text is really a link, a color or code.
enum KindDetector {
    private static let linkSchemes: Set<String> = ["http", "https", "ftp", "ftps", "mailto", "sftp", "ssh", "git"]

    /// A single-token URL with a real host (or a mailto: address).
    static func link(in text: String) -> URL? {
        guard !text.isEmpty, text.count <= 2_048, !text.contains(where: \.isWhitespace) else { return nil }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), linkSchemes.contains(scheme) else {
            return nil
        }
        if scheme == "mailto" {
            return text.contains("@") ? url : nil
        }
        guard let host = url.host(), host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    nonisolated(unsafe) private static let hexColor = #/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/#
    nonisolated(unsafe) private static let rgbColor = #/^rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*(?:[,/]\s*(0?\.\d+|1(?:\.0+)?|\d{1,3}%)\s*)?\)$/#
    nonisolated(unsafe) private static let hslColor = #/^hsla?\(\s*(\d{1,3}(?:\.\d+)?)\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%\s*(?:[,/]\s*(0?\.\d+|1(?:\.0+)?|\d{1,3}%)\s*)?\)$/#

    /// Normalised `#RRGGBB` or `#RRGGBBAA` when the text is a CSS-style color literal.
    static func color(in text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 40 else { return nil }

        if (try? hexColor.wholeMatch(in: value)) != nil {
            let digits = String(value.dropFirst())
            switch digits.count {
            case 3, 4:
                return "#" + digits.map { "\($0)\($0)" }.joined().uppercased()
            default:
                return "#" + digits.uppercased()
            }
        }

        if let match = try? rgbColor.wholeMatch(in: value) {
            guard let r = Int(match.1), let g = Int(match.2), let b = Int(match.3), r <= 255, g <= 255, b <= 255 else {
                return nil
            }
            return hexString(r: r, g: g, b: b, alpha: match.4.flatMap { alphaComponent(String($0)) })
        }

        if let match = try? hslColor.wholeMatch(in: value) {
            guard let h = Double(match.1), let s = Double(match.2), let l = Double(match.3), s <= 100, l <= 100 else {
                return nil
            }
            let (r, g, b) = hslToRGB(h: h.truncatingRemainder(dividingBy: 360), s: s / 100, l: l / 100)
            return hexString(r: r, g: g, b: b, alpha: match.4.flatMap { alphaComponent(String($0)) })
        }

        return nil
    }

    private static func alphaComponent(_ raw: String) -> Int? {
        if raw.hasSuffix("%"), let percent = Double(raw.dropLast()) {
            return Int((min(max(percent, 0), 100) / 100 * 255).rounded())
        }
        if let fraction = Double(raw) {
            return Int((min(max(fraction, 0), 1) * 255).rounded())
        }
        return nil
    }

    private static func hexString(r: Int, g: Int, b: Int, alpha: Int?) -> String {
        if let alpha, alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, alpha)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Int, Int, Int) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) = switch hp {
        case 0..<1: (c, x, 0)
        case 1..<2: (x, c, 0)
        case 2..<3: (0, c, x)
        case 3..<4: (0, x, c)
        case 4..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        func channel(_ v: Double) -> Int { Int(((v + m) * 255).rounded()) }
        return (channel(r1), channel(g1), channel(b1))
    }

    private static let codeLineStarts: [String] = [
        "$ ", "#!/", "import ", "from ", "func ", "def ", "class ", "struct ", "const ", "let ", "var ", "fn ",
        "package ", "use ", "#include", "SELECT ", "<?xml", "<!DOCTYPE", "enum ", "interface ", "public ", "private ",
        "export ", "@main", "<?php", "using ", "namespace ", "<html", "<div", "<svg",
    ]

    /// Apps whose copies are usually code.
    static let editorBundlePrefixes: [String] = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.jetbrains.", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "com.sublimetext.", "org.vim.", "com.neovide.", "com.github.atom",
    ]

    /// Conservative code detection: needs at least two lines and a score of 3 from independent
    /// signals, so prose with a stray semicolon stays "text".
    static func looksLikeCode(_ text: String, sourceBundleID: String? = nil, isRichText: Bool = false) -> Bool {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { String($0) }
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonEmpty.count >= 2 else { return isSingleLineCommand(text) }

        var score = 0

        if let sourceBundleID, editorBundlePrefixes.contains(where: { sourceBundleID.hasPrefix($0) }) { score += 2 }

        let indented = nonEmpty.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        if Double(indented) / Double(nonEmpty.count) >= 0.3 { score += 2 }

        let symbolCount = text.filter { "{}();=<>".contains($0) }.count
        if Double(symbolCount) >= 1.5 * Double(nonEmpty.count) { score += 1 }

        if let first = nonEmpty.first?.trimmingCharacters(in: .whitespaces),
           codeLineStarts.contains(where: { first.hasPrefix($0) }) { score += 1 }

        let punctuationEndings = nonEmpty.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{")
        }.count
        if punctuationEndings >= 2 { score += 1 }

        if isRichText { score -= 2 }

        return score >= 3
    }

    private static func isSingleLineCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 300, !trimmed.contains(where: \.isNewline) else { return false }
        let shellStarts = ["$ ", "npm ", "npx ", "brew ", "git ", "curl ", "docker ", "kubectl ", "xcodebuild ", "sudo ",
                           "pip ", "pip3 ", "cargo ", "go ", "swift ", "python ", "python3 ", "node ", "make ", "cd ",
                           "ls ", "rm ", "cp ", "mv ", "chmod ", "ssh ", "scp ", "tar ", "zip ", "open ", "defaults "]
        return shellStarts.contains { trimmed.hasPrefix($0) } && trimmed.contains(where: { "-/.".contains($0) })
    }
}
