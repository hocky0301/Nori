using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace Nori.Core;

/// <summary>
/// Windows "HTML Format" (CF_HTML) helpers: the payload is a small ASCII header (Version, StartHTML,
/// EndHTML, StartFragment, EndFragment) followed by UTF-8 HTML with fragment markers.
/// </summary>
public static partial class HtmlFormat
{
    [GeneratedRegex(@"<(script|style)[^>]*>.*?</\1>", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex ScriptOrStyle();

    [GeneratedRegex(@"<br\s*/?>|</p>|</div>|</li>|</tr>|</h[1-6]>", RegexOptions.IgnoreCase)]
    private static partial Regex BlockBreak();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex Tag();

    [GeneratedRegex(@"[ \t]+")]
    private static partial Regex Spaces();

    /// <summary>The HTML part of a CF_HTML payload (fragment when marked, else the whole document).</summary>
    public static string Fragment(byte[] payload)
    {
        var text = Encoding.UTF8.GetString(payload).TrimEnd('\0');
        var start = text.IndexOf("<!--StartFragment-->", StringComparison.OrdinalIgnoreCase);
        var end = text.IndexOf("<!--EndFragment-->", StringComparison.OrdinalIgnoreCase);
        if (start >= 0 && end > start)
        {
            return text[(start + "<!--StartFragment-->".Length)..end];
        }
        var html = text.IndexOf("<html", StringComparison.OrdinalIgnoreCase);
        if (html >= 0) return text[html..];
        var body = text.IndexOf('<');
        return body >= 0 ? text[body..] : text;
    }

    /// <summary>Plain text of an HTML snippet: tags stripped, entities decoded, block breaks kept as newlines.</summary>
    public static string ToPlainText(string html)
    {
        var s = ScriptOrStyle().Replace(html, string.Empty);
        s = BlockBreak().Replace(s, "\n");
        s = Tag().Replace(s, string.Empty);
        s = WebUtility.HtmlDecode(s);
        s = s.Replace("\r\n", "\n").Replace('\r', '\n').Replace('\u00A0', ' ');
        s = Spaces().Replace(s, " ");
        var lines = s.Split('\n').Select(l => l.Trim()).ToList();
        return string.Join('\n', lines).Trim();
    }

    /// <summary>Wraps an HTML fragment in the CF_HTML header expected by other apps.</summary>
    public static byte[] Encode(string fragment)
    {
        const string header = "Version:0.9\r\nStartHTML:{0:D10}\r\nEndHTML:{1:D10}\r\nStartFragment:{2:D10}\r\nEndFragment:{3:D10}\r\n";
        const string pre = "<html><body><!--StartFragment-->";
        const string post = "<!--EndFragment--></body></html>";
        var headerLength = string.Format(System.Globalization.CultureInfo.InvariantCulture, header, 0, 0, 0, 0).Length;
        var preBytes = Encoding.UTF8.GetByteCount(pre);
        var fragmentBytes = Encoding.UTF8.GetByteCount(fragment);
        var postBytes = Encoding.UTF8.GetByteCount(post);
        var startHtml = headerLength;
        var startFragment = startHtml + preBytes;
        var endFragment = startFragment + fragmentBytes;
        var endHtml = endFragment + postBytes;
        var text = string.Format(System.Globalization.CultureInfo.InvariantCulture, header, startHtml, endHtml, startFragment, endFragment) + pre + fragment + post;
        return Encoding.UTF8.GetBytes(text);
    }
}

/// <summary>Best-effort RTF inspection without a rich-text engine.</summary>
public static partial class RtfText
{
    [GeneratedRegex(@"\\(b0?|i0?|ul(?:none)?|strike0?|f\d+|fs\d+|cf\d+|cb\d+|highlight\d+|super|sub|nosupersub)(?=[^a-zA-Z0-9]|$)")]
    private static partial Regex FormattingWord();

    [GeneratedRegex(@"\{\\(fonttbl|colortbl|stylesheet|info|\*)[^{}]*(\{[^{}]*\})*[^{}]*\}")]
    private static partial Regex HeaderGroup();

    [GeneratedRegex(@"\\'[0-9a-fA-F]{2}")]
    private static partial Regex HexEscape();

    [GeneratedRegex(@"\\u(-?\d+)\??")]
    private static partial Regex UnicodeEscape();

    [GeneratedRegex(@"\\[a-zA-Z]+-?\d* ?")]
    private static partial Regex ControlWord();

    /// <summary>
    /// RTF whose only formatting is the default font is really plain text (terminals, plain-mode editors).
    /// "Rich" means the body switches at least one attribute: bold on/off, two font sizes, two colours, …
    /// </summary>
    public static bool IsMeaningfullyRich(byte[]? rtf)
    {
        if (rtf is null || rtf.Length == 0) return false;
        var text = Encoding.ASCII.GetString(rtf);
        if (!text.StartsWith("{\\rtf", StringComparison.Ordinal)) return false;
        var body = HeaderGroup().Replace(text, string.Empty);
        var families = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (System.Text.RegularExpressions.Match m in FormattingWord().Matches(body))
        {
            var word = m.Groups[1].Value;
            var family = new string(word.TakeWhile(char.IsLetter).ToArray());
            var value = word[family.Length..];
            if (family == "ul" && word == "ulnone") { family = "ul"; value = "0"; }
            if (family is "b" or "i" or "strike") value = value.Length == 0 ? "1" : value;
            if (family is "super" or "sub" or "nosupersub") { family = "script"; value = word; }
            if (!families.TryGetValue(family, out var values)) families[family] = values = [];
            values.Add(value);
        }
        return families.Values.Any(v => v.Count > 1);
    }

    /// <summary>Rough plain text of an RTF document (control words stripped, escapes decoded).</summary>
    public static string? ToPlainText(byte[]? rtf)
    {
        if (rtf is null || rtf.Length == 0) return null;
        var text = Encoding.ASCII.GetString(rtf);
        if (!text.StartsWith("{\\rtf", StringComparison.Ordinal)) return null;
        text = HeaderGroup().Replace(text, string.Empty);
        text = text.Replace("\\par\r\n", "\n").Replace("\\par\n", "\n").Replace("\\par ", "\n").Replace("\\line ", "\n");
        text = UnicodeEscape().Replace(text, m => ((char)int.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture)).ToString());
        text = HexEscape().Replace(text, m => ((char)Convert.ToInt32(m.Value[2..], 16)).ToString());
        text = ControlWord().Replace(text, string.Empty);
        text = text.Replace("{", string.Empty).Replace("}", string.Empty).Replace("\\\\", "\\");
        var result = text.Replace("\r\n", "\n").Trim();
        return result.Length == 0 ? null : result;
    }
}
