using System.Text.RegularExpressions;

namespace Nori.Core;

/// <summary>
/// High-precision detection of secrets that must never touch disk: private keys, cloud and
/// API tokens, JWTs and card numbers. Deliberately no entropy heuristics — git SHAs, UUIDs and
/// base64 blobs are everyday clipboard content and must not be hidden.
/// </summary>
public static partial class SecretDetector
{
    public enum Match
    {
        PrivateKey,
        AwsAccessKey,
        GitHubToken,
        GitHubFineGrainedToken,
        OpenAIKey,
        SlackToken,
        GoogleApiKey,
        Jwt,
        CardNumber,
    }

    [GeneratedRegex(@"-----BEGIN [A-Z ]*PRIVATE KEY-----")]
    private static partial Regex PrivateKey();

    [GeneratedRegex(@"\bAKIA[0-9A-Z]{16}\b")]
    private static partial Regex AwsAccessKey();

    [GeneratedRegex(@"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b")]
    private static partial Regex GitHubToken();

    [GeneratedRegex(@"\bgithub_pat_[A-Za-z0-9_]{22,}\b")]
    private static partial Regex GitHubFineGrainedToken();

    [GeneratedRegex(@"\bsk-[A-Za-z0-9_-]{32,}\b")]
    private static partial Regex OpenAIKey();

    [GeneratedRegex(@"\bxox[abpr]-[A-Za-z0-9-]{10,}\b")]
    private static partial Regex SlackToken();

    [GeneratedRegex(@"\bAIza[0-9A-Za-z_-]{35}\b")]
    private static partial Regex GoogleApiKey();

    [GeneratedRegex(@"^eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}$")]
    private static partial Regex Jwt();

    private static readonly (Match Match, Regex Regex)[] Patterns =
    [
        (Match.PrivateKey, PrivateKey()),
        (Match.AwsAccessKey, AwsAccessKey()),
        (Match.GitHubToken, GitHubToken()),
        (Match.GitHubFineGrainedToken, GitHubFineGrainedToken()),
        (Match.OpenAIKey, OpenAIKey()),
        (Match.SlackToken, SlackToken()),
        (Match.GoogleApiKey, GoogleApiKey()),
        (Match.Jwt, Jwt()),
    ];

    public static Match? Detect(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed.Length > 20_000) return null;
        foreach (var (match, regex) in Patterns)
        {
            if (regex.IsMatch(trimmed)) return match;
        }
        return IsCardNumber(trimmed) ? Match.CardNumber : null;
    }

    /// <summary>13–19 digits (spaces or dashes allowed) that pass Luhn.</summary>
    public static bool IsCardNumber(string text)
    {
        if (text.Length > 25 || !text.All(c => char.IsAsciiDigit(c) || c == ' ' || c == '-')) return false;
        var digits = text.Where(char.IsAsciiDigit).Select(c => c - '0').ToArray();
        if (digits.Length is < 13 or > 19) return false;
        return LuhnValid(digits);
    }

    public static bool LuhnValid(IReadOnlyList<int> digits)
    {
        var sum = 0;
        var offset = 0;
        for (var i = digits.Count - 1; i >= 0; i--, offset++)
        {
            var digit = digits[i];
            if (offset % 2 == 1)
            {
                var doubled = digit * 2;
                sum += doubled > 9 ? doubled - 9 : doubled;
            }
            else
            {
                sum += digit;
            }
        }
        return sum % 10 == 0;
    }

    /// <summary>Everything but the last four characters becomes <c>•</c>, grouped in fours.</summary>
    public static string Mask(string text)
    {
        var compact = new string(text.Trim().Where(c => !char.IsWhiteSpace(c) && c != '-').ToArray());
        var visible = compact.Length <= 4 ? compact : compact[^4..];
        var hiddenCount = Math.Min(Math.Max(compact.Length - 4, 4), 16);
        var groups = new List<string>();
        var remaining = hiddenCount;
        while (remaining > 0)
        {
            var take = Math.Min(4, remaining);
            groups.Add(new string('•', take));
            remaining -= take;
        }
        groups.Add(visible);
        return string.Join(' ', groups);
    }

    /// <summary>Resource key of the human-readable label ("Private key", "Card number", …).</summary>
    public static string LabelKey(Match match) => match switch
    {
        Match.PrivateKey => "Secret_PrivateKey",
        Match.AwsAccessKey => "Secret_AwsAccessKey",
        Match.GitHubToken or Match.GitHubFineGrainedToken => "Secret_GitHubToken",
        Match.OpenAIKey => "Secret_ApiKey",
        Match.SlackToken => "Secret_SlackToken",
        Match.GoogleApiKey => "Secret_GoogleApiKey",
        Match.Jwt => "Secret_AccessToken",
        Match.CardNumber => "Secret_CardNumber",
        _ => "Secret_ApiKey",
    };
}
