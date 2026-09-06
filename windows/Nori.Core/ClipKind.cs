namespace Nori.Core;

/// <summary>
/// The user-facing category of a clipboard item. Every capture is classified once so the panel
/// can render a tailored card and the user can filter by kind. Rich text is a flag on Text, not a kind.
/// </summary>
public enum ClipKind
{
    Text = 0,
    Link = 1,
    Code = 2,
    Color = 3,
    Image = 4,
    File = 5,
}

public static class ClipKindExtensions
{
    /// <summary>Whether the item carries a textual payload that can be pasted as plain text.</summary>
    public static bool IsTextual(this ClipKind kind) => kind is ClipKind.Text or ClipKind.Code or ClipKind.Link or ClipKind.Color;
}

/// <summary>The chips above the list. Pinned is a section, not a filter.</summary>
public enum PanelFilter
{
    All = 0,
    Text,
    Link,
    Code,
    Color,
    Image,
    File,
}

public static class PanelFilterExtensions
{
    public static readonly IReadOnlyList<PanelFilter> AllFilters =
    [
        PanelFilter.All, PanelFilter.Text, PanelFilter.Link, PanelFilter.Code, PanelFilter.Color, PanelFilter.Image, PanelFilter.File,
    ];

    public static ClipKind? Kind(this PanelFilter filter) => filter switch
    {
        PanelFilter.Text => ClipKind.Text,
        PanelFilter.Link => ClipKind.Link,
        PanelFilter.Code => ClipKind.Code,
        PanelFilter.Color => ClipKind.Color,
        PanelFilter.Image => ClipKind.Image,
        PanelFilter.File => ClipKind.File,
        _ => null,
    };

    public static bool Matches(this PanelFilter filter, ClipKind kind) => filter.Kind() is null || filter.Kind() == kind;

    public static PanelFilter Next(this PanelFilter filter) => (PanelFilter)(((int)filter + 1) % AllFilters.Count);

    public static PanelFilter Previous(this PanelFilter filter) => (PanelFilter)(((int)filter + AllFilters.Count - 1) % AllFilters.Count);
}
