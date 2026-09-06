using System.Globalization;
using System.Text.RegularExpressions;

namespace Nori.Core;

/// <summary>Heuristics that decide whether a piece of text is really a link, a color or code.</summary>
public static partial class KindDetector
{
    private static readonly HashSet<string> LinkSchemes = new(StringComparer.OrdinalIgnoreCase)
    {
        "http", "https", "ftp", "ftps", "mailto", "sftp", "ssh", "git",
    };

    /// <summary>A single-token URL with a real host (or a mailto: address).</summary>
    public static Uri? Link(string text)
    {
        if (string.IsNullOrEmpty(text) || text.Length > 2048 || text.Any(char.IsWhiteSpace)) return null;
        if (!Uri.TryCreate(text, UriKind.Absolute, out var url)) return null;
        var scheme = url.Scheme;
        if (!LinkSchemes.Contains(scheme)) return null;
        if (scheme.Equals("mailto", StringComparison.OrdinalIgnoreCase))
        {
            return text.Contains('@') ? url : null;
        }
        var host = url.Host;
        if (string.IsNullOrEmpty(host)) return null;
        if (!host.Contains('.') && !host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return null;
        return url;
    }

    [GeneratedRegex(@"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")]
    private static partial Regex HexColor();

    [GeneratedRegex(@"^rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*(?:[,/]\s*(0?\.\d+|1(?:\.0+)?|\d{1,3}%)\s*)?\)$", RegexOptions.IgnoreCase)]
    private static partial Regex RgbColor();

    [GeneratedRegex(@"^hsla?\(\s*(\d{1,3}(?:\.\d+)?)\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%\s*(?:[,/]\s*(0?\.\d+|1(?:\.0+)?|\d{1,3}%)\s*)?\)$", RegexOptions.IgnoreCase)]
    private static partial Regex HslColor();

    /// <summary>Normalised <c>#RRGGBB</c> or <c>#RRGGBBAA</c> when the text is a CSS-style color literal.</summary>
    public static string? Color(string text)
    {
        var value = text.Trim();
        if (value.Length > 40) return null;

        if (HexColor().IsMatch(value))
        {
            var digits = value[1..];
            if (digits.Length is 3 or 4)
            {
                return "#" + string.Concat(digits.Select(c => $"{c}{c}")).ToUpperInvariant();
            }
            return "#" + digits.ToUpperInvariant();
        }

        var rgb = RgbColor().Match(value);
        if (rgb.Success)
        {
            var r = int.Parse(rgb.Groups[1].Value, CultureInfo.InvariantCulture);
            var g = int.Parse(rgb.Groups[2].Value, CultureInfo.InvariantCulture);
            var b = int.Parse(rgb.Groups[3].Value, CultureInfo.InvariantCulture);
            if (r > 255 || g > 255 || b > 255) return null;
            return HexString(r, g, b, rgb.Groups[4].Success ? AlphaComponent(rgb.Groups[4].Value) : null);
        }

        var hsl = HslColor().Match(value);
        if (hsl.Success)
        {
            var h = double.Parse(hsl.Groups[1].Value, CultureInfo.InvariantCulture);
            var s = double.Parse(hsl.Groups[2].Value, CultureInfo.InvariantCulture);
            var l = double.Parse(hsl.Groups[3].Value, CultureInfo.InvariantCulture);
            if (s > 100 || l > 100) return null;
            var (r, g, b) = HslToRgb(h % 360, s / 100, l / 100);
            return HexString(r, g, b, hsl.Groups[4].Success ? AlphaComponent(hsl.Groups[4].Value) : null);
        }

        return null;
    }

    private static int? AlphaComponent(string raw)
    {
        if (raw.EndsWith('%') && double.TryParse(raw[..^1], NumberStyles.Float, CultureInfo.InvariantCulture, out var percent))
        {
            return (int)Math.Round(Math.Clamp(percent, 0, 100) / 100 * 255, MidpointRounding.AwayFromZero);
        }
        if (double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var fraction))
        {
            return (int)Math.Round(Math.Clamp(fraction, 0, 1) * 255, MidpointRounding.AwayFromZero);
        }
        return null;
    }

    private static string HexString(int r, int g, int b, int? alpha)
    {
        if (alpha is { } a && a < 255)
        {
            return $"#{r:X2}{g:X2}{b:X2}{a:X2}";
        }
        return $"#{r:X2}{g:X2}{b:X2}";
    }

    private static (int R, int G, int B) HslToRgb(double h, double s, double l)
    {
        var c = (1 - Math.Abs(2 * l - 1)) * s;
        var hp = h / 60;
        var x = c * (1 - Math.Abs(hp % 2 - 1));
        var (r1, g1, b1) = hp switch
        {
            < 1 => (c, x, 0.0),
            < 2 => (x, c, 0.0),
            < 3 => (0.0, c, x),
            < 4 => (0.0, x, c),
            < 5 => (x, 0.0, c),
            _ => (c, 0.0, x),
        };
        var m = l - c / 2;
        static int Channel(double v, double m) => (int)Math.Round((v + m) * 255, MidpointRounding.AwayFromZero);
        return (Channel(r1, m), Channel(g1, m), Channel(b1, m));
    }

    /// <summary>Converts a normalised hex string back to channels (for rgb()/hsl() captions).</summary>
    public static (int R, int G, int B, int A)? Channels(string hex)
    {
        if (hex.Length is not (7 or 9) || hex[0] != '#') return null;
        if (!int.TryParse(hex.AsSpan(1, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var r)) return null;
        if (!int.TryParse(hex.AsSpan(3, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var g)) return null;
        if (!int.TryParse(hex.AsSpan(5, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var b)) return null;
        var a = 255;
        if (hex.Length == 9 && !int.TryParse(hex.AsSpan(7, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out a)) return null;
        return (r, g, b, a);
    }

    /// <summary>"rgb(255, 107, 53)" for the color card caption.</summary>
    public static string RgbText(string hex)
    {
        if (Channels(hex) is not { } c) return string.Empty;
        return c.A < 255
            ? string.Create(CultureInfo.InvariantCulture, $"rgba({c.R}, {c.G}, {c.B}, {c.A / 255.0:0.##})")
            : string.Create(CultureInfo.InvariantCulture, $"rgb({c.R}, {c.G}, {c.B})");
    }

    /// <summary>"hsl(21, 100%, 60%)" for the expanded color preview.</summary>
    public static string HslText(string hex)
    {
        if (Channels(hex) is not { } c) return string.Empty;
        double r = c.R / 255.0, g = c.G / 255.0, b = c.B / 255.0;
        var max = Math.Max(r, Math.Max(g, b));
        var min = Math.Min(r, Math.Min(g, b));
        var l = (max + min) / 2;
        double h = 0, s = 0;
        var d = max - min;
        if (d > 0)
        {
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max == r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (max == g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h *= 60;
        }
        return string.Create(CultureInfo.InvariantCulture, $"hsl({Math.Round(h)}, {Math.Round(s * 100)}%, {Math.Round(l * 100)}%)");
    }

    private static readonly string[] CodeLineStarts =
    [
        "$ ", "#!/", "import ", "from ", "func ", "def ", "class ", "struct ", "const ", "let ", "var ", "fn ",
        "package ", "use ", "#include", "SELECT ", "<?xml", "<!DOCTYPE", "enum ", "interface ", "public ", "private ",
        "export ", "@main", "<?php", "using ", "namespace ", "<html", "<div", "<svg",
    ];

    /// <summary>Executables (or name prefixes) whose copies are usually code: editors and terminals.</summary>
    public static readonly IReadOnlyList<string> EditorProcessPrefixes =
    [
        "Code.exe", "Code - Insiders.exe", "devenv.exe", "Cursor.exe", "zed.exe", "idea64.exe", "rider64.exe",
        "pycharm64.exe", "webstorm64.exe", "clion64.exe", "goland64.exe", "phpstorm64.exe", "sublime_text.exe",
        "notepad++.exe", "WindowsTerminal.exe", "cmd.exe", "powershell.exe", "pwsh.exe", "mintty.exe",
        "alacritty.exe", "wezterm-gui.exe", "nvim", "gvim.exe", "vim.exe", "neovide.exe", "conhost.exe",
        // macOS bundle identifiers keep the classifier fixtures shared with the Mac test corpus.
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.jetbrains.", "com.apple.Terminal",
    ];

    /// <summary>
    /// Conservative code detection: needs at least two lines and a score of 3 from independent
    /// signals, so prose with a stray semicolon stays "text".
    /// </summary>
    public static bool LooksLikeCode(string text, string? sourceApp = null, bool isRichText = false)
    {
        var lines = SplitLines(text);
        var nonEmpty = lines.Where(l => l.Trim(' ', '\t').Length > 0).ToList();
        if (nonEmpty.Count < 2) return IsSingleLineCommand(text);

        var score = 0;

        if (sourceApp is not null && EditorProcessPrefixes.Any(p => sourceApp.StartsWith(p, StringComparison.OrdinalIgnoreCase))) score += 2;

        var indented = nonEmpty.Count(l => l.StartsWith("  ", StringComparison.Ordinal) || l.StartsWith('\t'));
        if ((double)indented / nonEmpty.Count >= 0.3) score += 2;

        var symbolCount = text.Count(c => "{}();=<>".Contains(c));
        if (symbolCount >= 1.5 * nonEmpty.Count) score += 1;

        var first = nonEmpty[0].Trim(' ', '\t');
        if (CodeLineStarts.Any(s => first.StartsWith(s, StringComparison.Ordinal))) score += 1;

        var punctuationEndings = nonEmpty.Count(l =>
        {
            var trimmed = l.Trim(' ', '\t');
            return trimmed.EndsWith(';') || trimmed.EndsWith('{');
        });
        if (punctuationEndings >= 2) score += 1;

        if (isRichText) score -= 2;

        return score >= 3;
    }

    private static readonly string[] ShellStarts =
    [
        "$ ", "npm ", "npx ", "brew ", "git ", "curl ", "docker ", "kubectl ", "xcodebuild ", "sudo ",
        "pip ", "pip3 ", "cargo ", "go ", "swift ", "python ", "python3 ", "node ", "make ", "cd ",
        "ls ", "rm ", "cp ", "mv ", "chmod ", "ssh ", "scp ", "tar ", "zip ", "open ", "defaults ",
        "dotnet ", "winget ", "choco ", "scoop ", "wsl ", "pwsh ", "dir ", "del ", "copy ", "move ", "Get-", "Set-",
    ];

    private static bool IsSingleLineCommand(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length > 300 || trimmed.Any(IsNewline)) return false;
        return ShellStarts.Any(s => trimmed.StartsWith(s, StringComparison.Ordinal)) && trimmed.Any(c => "-/.".Contains(c));
    }

    public static bool IsNewline(char c) => c is '\n' or '\r' or '\u2028' or '\u2029' or '\u0085' or '\u000B' or '\u000C';

    /// <summary>Splits on every Unicode line terminator, treating CRLF as one break.</summary>
    public static List<string> SplitLines(string text)
    {
        var result = new List<string>();
        var start = 0;
        for (var i = 0; i < text.Length; i++)
        {
            if (!IsNewline(text[i])) continue;
            result.Add(text[start..i]);
            if (text[i] == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
            start = i + 1;
        }
        result.Add(text[start..]);
        return result;
    }
}
