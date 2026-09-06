using Nori.Core;
using Nori.Windows.Clipboard;

namespace Nori.Windows;

/// <summary>
/// Turns clipboard changes into history rows, vault entries or ghost rows, and owns the pause /
/// skip-next state. Everything runs on the UI thread; the heavy lifting is the pure classifier.
/// </summary>
internal sealed class CaptureService
{
    private readonly NoriSettings _settings;
    private readonly HistoryStore _history;
    private readonly SensitiveVault _vault;
    private readonly SourceApps _apps;
    private readonly IClock _clock;
    private readonly List<ClipRow> _ghosts = [];
    private bool _ghostsShown;

    public const int MaxGhostRows = 5;

    public CaptureService(NoriSettings settings, HistoryStore history, SensitiveVault vault, SourceApps apps, IClock clock)
    {
        _settings = settings;
        _history = history;
        _vault = vault;
        _apps = apps;
        _clock = clock;
    }

    /// <summary>Raised whenever rows changed (history, vault or ghosts).</summary>
    public event Action? Changed;

    /// <summary>Raised when the pause state changed (tray icon, search placeholder).</summary>
    public event Action? PauseChanged;

    public IReadOnlyList<ClipRow> Ghosts => _settings.ShowGhostRows ? _ghosts : [];

    /// <summary>null = capturing; <see cref="DateTimeOffset.MaxValue"/> = until resumed.</summary>
    public DateTimeOffset? PauseUntil { get; private set; }

    public bool SkipNextCopy { get; set; }

    public bool IsPaused
    {
        get
        {
            if (PauseUntil is not { } until) return false;
            if (until > _clock.Now) return true;
            PauseUntil = null; // expired silently
            PauseChanged?.Invoke();
            return false;
        }
    }

    public TimeSpan? PauseRemaining => PauseUntil is { } until && until != DateTimeOffset.MaxValue && until > _clock.Now ? until - _clock.Now : null;

    public void Pause(TimeSpan? duration)
    {
        PauseUntil = duration is { } d ? _clock.Now + d : DateTimeOffset.MaxValue;
        PauseChanged?.Invoke();
    }

    public void Resume()
    {
        PauseUntil = null;
        PauseChanged?.Invoke();
    }

    public int NotSavedToday => _settings.NotSavedToday(_clock.Now);

    /// <summary>WM_CLIPBOARDUPDATE handler.</summary>
    public void OnClipboardUpdated()
    {
        if (IsPaused) return;
        if (SkipNextCopy)
        {
            SkipNextCopy = false;
            return;
        }
        ClipboardSnapshot? snapshot;
        try
        {
            snapshot = ClipboardReader.Read(_apps, _clock);
        }
        catch (Exception e)
        {
            Log.Error("clipboard read failed", e);
            return;
        }
        if (snapshot is null) return;
        Process(snapshot);
    }

    public void Process(ClipboardSnapshot snapshot)
    {
        CaptureOutcome outcome;
        try
        {
            outcome = ClipClassifier.Classify(snapshot, _settings.ToCapturePolicy(), WpfImageNormalizer.Instance);
        }
        catch (Exception e)
        {
            Log.Error("classification failed", e);
            return;
        }
        var now = _clock.Now;
        switch (outcome)
        {
            case CaptureOutcome.Captured captured:
                _history.Ingest(captured.Draft, now);
                Changed?.Invoke();
                break;
            case CaptureOutcome.Sensitive sensitive:
                _vault.Add(sensitive.Draft, now);
                Changed?.Invoke();
                break;
            case CaptureOutcome.Ghost ghost:
                AddGhost(ghost.Reason, now);
                break;
            case CaptureOutcome.Rejected rejected:
                if (rejected.Rejection is CaptureRejection.FromNori)
                {
                    // Our own write: the item was touched when it was pasted.
                    return;
                }
                Log.Info($"copy not recorded: {rejected.Rejection}");
                break;
        }
    }

    public void AddGhost(GhostReason reason, DateTimeOffset at)
    {
        _ghosts.Insert(0, ClipRow.Ghost(reason, at));
        if (_ghosts.Count > MaxGhostRows) _ghosts.RemoveRange(MaxGhostRows, _ghosts.Count - MaxGhostRows);
        _settings.IncrementNotSaved(at);
        _ghostsShown = false;
        Changed?.Invoke();
    }

    /// <summary>The panel calls this when it opens (ghosts were displayed) and when it closes (they go away).</summary>
    public void PanelOpened() => _ghostsShown = _ghosts.Count > 0;

    public void PanelClosed()
    {
        if (!_ghostsShown || _ghosts.Count == 0) return;
        _ghosts.Clear();
        _ghostsShown = false;
        Changed?.Invoke();
    }

    /// <summary>30-second timer tick: expired secrets disappear.</summary>
    public void SweepVault()
    {
        var before = _vault.Version;
        _vault.Sweep(_clock.Now);
        if (_vault.Version != before) Changed?.Invoke();
    }

    public void NotifyChanged() => Changed?.Invoke();
}
