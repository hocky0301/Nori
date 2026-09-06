namespace Nori.Core;

/// <summary>
/// Clipboard format names Nori cares about, as plain strings so the capture pipeline can be
/// tested without touching the real clipboard. Names follow the Windows registered-format
/// conventions (the WPF <c>DataFormats</c> names for the predefined formats).
/// </summary>
public static class ClipboardFormats
{
    public const string UnicodeText = "UnicodeText";          // CF_UNICODETEXT
    public const string Html = "HTML Format";                 // CF_HTML (with the StartHTML/EndHTML header)
    public const string Rtf = "Rich Text Format";
    public const string Png = "PNG";
    public const string Dib = "DeviceIndependentBitmap";      // CF_DIB; converted to PNG at capture
    public const string Bitmap = "Bitmap";                    // CF_BITMAP; converted to PNG at capture
    public const string FileDrop = "FileDrop";                // CF_HDROP; one representation per file, payload = UTF-8 path

    /// <summary>Written by Nori when it puts an item back on the clipboard. The payload is the item GUID.</summary>
    public const string NoriItem = "Nori.Item";

    /// <summary>Windows' own privacy markers (set by password managers and Windows itself).</summary>
    public const string ExcludeFromMonitoring = "ExcludeClipboardContentFromMonitorProcessing";
    public const string CanIncludeInHistory = "CanIncludeInClipboardHistory";
    public const string CanUploadToCloud = "CanUploadToCloudClipboard";

    /// <summary>
    /// Formats that describe <em>this</em> copy rather than the content; never stored, never hashed.
    /// </summary>
    public static readonly IReadOnlySet<string> MetadataFormats = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        NoriItem,
        ExcludeFromMonitoring,
        CanIncludeInHistory,
        CanUploadToCloud,
        "Locale",
        "OEMText",
        "Text",
        "DataObject",
        "Object Descriptor",
        "Link Source Descriptor",
        "Ole Private Data",
        "Shell IDList Array",
        "Preferred DropEffect",
        "DragContext",
        "DragImageBits",
        "Chromium internal source URL",
        "Chromium Web Custom MIME Data Format",
        "msSourceUrl",
        "text/x-moz-url-priv",
        "text/_moz_htmlcontext",
        "text/_moz_htmlinfo",
    };

    /// <summary>Custom formats used by password managers and snippet tools. Skipped by default; user-editable.</summary>
    public static readonly IReadOnlyList<string> DefaultIgnoredFormats =
    [
        "Clipboard Viewer Ignore",
        "1Password.Clipboard",
        "Bitwarden",
        "KeePass",
        "KeePassXC",
    ];

    /// <summary>Password managers whose copies are never recorded by default (executable names).</summary>
    public static readonly IReadOnlyList<string> DefaultIgnoredApps =
    [
        "1Password.exe",
        "Bitwarden.exe",
        "KeePassXC.exe",
        "KeePass.exe",
        "Dashlane.exe",
        "LastPass.exe",
    ];

    public static readonly IReadOnlyList<string> ImageFormats = [Png, Dib, Bitmap];
    public static readonly IReadOnlyList<string> TextFormats = [UnicodeText, Rtf, Html];

    /// <summary>Representations that participate in duplicate detection.</summary>
    public static readonly IReadOnlySet<string> StableFormats =
        new HashSet<string>(ImageFormats.Concat(TextFormats).Append(FileDrop), StringComparer.OrdinalIgnoreCase);

    /// <summary>Prefixes of per-process dynamic formats that are meaningless after the copying app quits.</summary>
    public static readonly IReadOnlyList<string> IgnoredPrefixes = ["Format", "Embed Source", "Native", "OwnerLink", "ObjectLink", "Link Source"];

    /// <summary>Microsoft Word bookmark/cross-reference formats that make Word paste a link instead of text.</summary>
    public static readonly IReadOnlySet<string> MicrosoftLinkFormats = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "ObjectLink", "Link Source",
    };

    public static bool IsImage(string format) => ImageFormats.Contains(format, StringComparer.OrdinalIgnoreCase);
    public static bool IsText(string format) => TextFormats.Contains(format, StringComparer.OrdinalIgnoreCase);
    public static bool Is(string format, string other) => string.Equals(format, other, StringComparison.OrdinalIgnoreCase);
}

/// <summary>An injectable clock so relative times and expiry are deterministic in tests and screenshots.</summary>
public interface IClock
{
    DateTimeOffset Now { get; }
}

public sealed class SystemClock : IClock
{
    public static readonly SystemClock Instance = new();
    public DateTimeOffset Now => DateTimeOffset.Now;
}

public sealed class FixedClock(DateTimeOffset now) : IClock
{
    public DateTimeOffset Now { get; set; } = now;
}
