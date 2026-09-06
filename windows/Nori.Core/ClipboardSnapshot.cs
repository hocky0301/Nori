using System.Text;

namespace Nori.Core;

/// <summary>
/// A value copy of everything on the clipboard at one moment. Reading the clipboard has to happen
/// on the UI thread; everything after that (classification, hashing, ignore rules) works on this value.
/// </summary>
public sealed class ClipboardSnapshot
{
    /// <summary>One data object on the clipboard: formats in declaration order, mapped to bytes (null when the app refused to provide data).</summary>
    public sealed class Item(IReadOnlyList<(string Format, byte[]? Data)> representations)
    {
        public IReadOnlyList<(string Format, byte[]? Data)> Representations { get; } = representations;

        public IEnumerable<string> Formats => Representations.Select(r => r.Format);

        public byte[]? Data(string format) =>
            Representations.FirstOrDefault(r => ClipboardFormats.Is(r.Format, format)).Data;

        public string? String(string format)
        {
            var data = Data(format);
            return data is null ? null : Encoding.UTF8.GetString(data);
        }
    }

    public ClipboardSnapshot(
        IReadOnlySet<string> declaredFormats,
        IReadOnlyList<Item> items,
        string? sourceApp,
        string? sourceAppName = null,
        string? sourceAppPath = null,
        DateTimeOffset? capturedAt = null,
        bool canIncludeInHistory = true)
    {
        DeclaredFormats = declaredFormats;
        Items = items;
        SourceApp = sourceApp;
        SourceAppName = sourceAppName;
        SourceAppPath = sourceAppPath;
        CapturedAt = capturedAt ?? DateTimeOffset.Now;
        CanIncludeInHistory = canIncludeInHistory;
    }

    /// <summary>Clipboard-level formats (a superset of every item's formats; some apps declare formats they never provide).</summary>
    public IReadOnlySet<string> DeclaredFormats { get; }
    public IReadOnlyList<Item> Items { get; }

    /// <summary>Executable name of the clipboard owner (e.g. <c>chrome.exe</c>).</summary>
    public string? SourceApp { get; }
    public string? SourceAppName { get; }
    public string? SourceAppPath { get; }
    public DateTimeOffset CapturedAt { get; }

    /// <summary>False when the owner wrote <c>CanIncludeInClipboardHistory</c> = 0.</summary>
    public bool CanIncludeInHistory { get; }

    public bool HasNoriMarker => DeclaredFormats.Contains(ClipboardFormats.NoriItem);

    /// <summary>The GUID Nori wrote when it restored an item, if this change came from Nori itself.</summary>
    public Guid? NoriItemId
    {
        get
        {
            foreach (var item in Items)
            {
                var text = item.String(ClipboardFormats.NoriItem)?.Trim('\0', ' ', '\r', '\n');
                if (text is not null && Guid.TryParse(text, out var id)) return id;
            }
            return null;
        }
    }

    /// <summary>Convenience for tests and seeding: one item built from a list of representations.</summary>
    public static ClipboardSnapshot Single(IReadOnlyList<(string Format, byte[]? Data)> representations, string? sourceApp = null, string? sourceAppName = null)
    {
        var item = new Item(representations);
        return new ClipboardSnapshot(new HashSet<string>(item.Formats, StringComparer.OrdinalIgnoreCase), [item], sourceApp, sourceAppName);
    }
}
