using System.Globalization;
using System.Resources;

namespace Nori.Windows.Resources;

/// <summary>Every UI string, resolved from Strings.resx / Strings.ja.resx by the current UI culture.</summary>
internal static class Strings
{
    private static readonly ResourceManager Manager = new("Nori.Windows.Resources.Strings", typeof(Strings).Assembly);

    /// <summary>Set once at startup; screenshot mode pins it to English so CI images are stable.</summary>
    public static CultureInfo Culture { get; set; } = CultureInfo.CurrentUICulture;

    public static string Get(string key)
    {
        try
        {
            return Manager.GetString(key, Culture) ?? key;
        }
        catch (MissingManifestResourceException)
        {
            return key;
        }
    }

    public static string Format(string key, params object[] args) =>
        string.Format(Culture, Get(key), args);

    public static bool IsJapanese => Culture.TwoLetterISOLanguageName == "ja";
}
