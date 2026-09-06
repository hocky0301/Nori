namespace Nori.Core;

/// <summary>User-configurable rules that decide whether a clipboard change is worth keeping.</summary>
public sealed record CapturePolicy
{
    /// <summary>Custom clipboard formats whose presence means "do not record this copy".</summary>
    public IReadOnlySet<string> IgnoredFormats { get; init; } =
        new HashSet<string>(ClipboardFormats.DefaultIgnoredFormats, StringComparer.OrdinalIgnoreCase);

    /// <summary>Executable names of apps whose copies are never recorded.</summary>
    public IReadOnlySet<string> IgnoredApps { get; init; } =
        new HashSet<string>(ClipboardFormats.DefaultIgnoredApps, StringComparer.OrdinalIgnoreCase);

    /// <summary>Regular expressions; a plain-text item matching any of them is dropped.</summary>
    public IReadOnlyList<string> IgnoreRegexes { get; init; } = [];

    public bool CaptureText { get; init; } = true;
    public bool CaptureImages { get; init; } = true;
    public bool CaptureFiles { get; init; } = true;

    /// <summary>Detect secrets and keep them in memory only (masked).</summary>
    public bool MaskSensitive { get; init; } = true;

    /// <summary>Images above this size are not stored (a ghost row explains why).</summary>
    public int MaxImageBytes { get; init; } = 10 * 1024 * 1024;

    /// <summary>Plain text above this size is truncated (and RTF/HTML dropped).</summary>
    public int MaxTextBytes { get; init; } = 2 * 1024 * 1024;

    /// <summary>Any other single representation above this size is dropped from the clip.</summary>
    public int MaxOtherRepresentationBytes { get; init; } = 1 * 1024 * 1024;

    public static readonly CapturePolicy Default = new();
}

/// <summary>Why a clipboard change was not recorded.</summary>
public abstract record CaptureRejection
{
    public sealed record FromNori(Guid? ItemId) : CaptureRejection;
    public sealed record Ephemeral(string Format) : CaptureRejection;
    public sealed record IgnoredFormat(string Format) : CaptureRejection;
    public sealed record IgnoredApp(string App) : CaptureRejection;
    public sealed record MatchedIgnoreRegex : CaptureRejection;
    public sealed record NothingToStore : CaptureRejection;
}

/// <summary>A copy that was deliberately not kept, but should leave a visible trace.</summary>
public abstract record GhostReason
{
    public sealed record Concealed(string? AppName) : GhostReason;
    public sealed record ImageTooLarge(long Bytes) : GhostReason;
}

public abstract record CaptureOutcome
{
    public sealed record Captured(ClipDraft Draft) : CaptureOutcome;
    public sealed record Sensitive(SensitiveDraft Draft) : CaptureOutcome;
    public sealed record Ghost(GhostReason Reason) : CaptureOutcome;
    public sealed record Rejected(CaptureRejection Rejection) : CaptureOutcome;
}
