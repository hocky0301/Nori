namespace Nori.Core;

public enum EmptyState
{
    None,
    NothingCopied,
    NoMatches,
    FilterEmpty,
}

/// <summary>
/// The panel's view state: rows, filter, query, selection, expansion and the modifier bits the hint
/// bar mirrors. Everything the keyboard map changes lives here so it can be tested without a window.
/// </summary>
public sealed class PanelModel
{
    private IReadOnlyList<ClipRow> _history = [];
    private IReadOnlyList<ClipRow> _sensitive = [];
    private IReadOnlyList<ClipRow> _ghosts = [];
    private IReadOnlyList<PanelSections.Section> _sections = [];
    private IReadOnlyList<PanelSections.Row> _visible = [];
    private readonly TimeZoneInfo _timeZone;

    public PanelModel(IClock clock, TimeZoneInfo? timeZone = null)
    {
        Clock = clock;
        _timeZone = timeZone ?? TimeZoneInfo.Local;
    }

    public IClock Clock { get; }
    public PanelFilter Filter { get; private set; } = PanelFilter.All;
    public string Query { get; private set; } = string.Empty;
    public Guid? SelectedId { get; private set; }
    public Guid? ExpandedId { get; private set; }
    public ActionGrammar.Bits Modifiers { get; private set; }

    /// <summary>Bumped whenever something visible changed.</summary>
    public int Version { get; private set; }

    public IReadOnlyList<PanelSections.Section> Sections => _sections;

    /// <summary>Selectable rows in display order (ghosts excluded).</summary>
    public IReadOnlyList<PanelSections.Row> VisibleRows => _visible;

    public PanelSections.Row? Selected => SelectedId is { } id ? _visible.FirstOrDefault(r => r.Id == id) : null;
    public int SelectedIndex => SelectedId is { } id ? IndexOf(id) : -1;
    public bool IsSearching => Query.Trim().Length > 0;
    public bool IsExpanded => ExpandedId is not null && ExpandedId == SelectedId;

    public EmptyState EmptyState
    {
        get
        {
            if (_visible.Count > 0 || _sections.Count > 0) return EmptyState.None;
            if (_history.Count == 0 && _sensitive.Count == 0) return EmptyState.NothingCopied;
            if (IsSearching) return EmptyState.NoMatches;
            return Filter == PanelFilter.All ? EmptyState.NothingCopied : EmptyState.FilterEmpty;
        }
    }

    /// <summary>Enter with a query that matches nothing pastes the query itself as text.</summary>
    public bool ShouldPasteTypedText => IsSearching && _visible.Count == 0;

    public void SetRows(IReadOnlyList<ClipRow> history, IReadOnlyList<ClipRow> sensitive, IReadOnlyList<ClipRow> ghosts)
    {
        _history = history;
        _sensitive = sensitive;
        _ghosts = ghosts;
        Rebuild(keepSelection: true);
    }

    /// <summary>Every open starts clean: empty search, All, first row selected, nothing expanded.</summary>
    public void Open()
    {
        Query = string.Empty;
        Filter = PanelFilter.All;
        ExpandedId = null;
        Modifiers = ActionGrammar.Bits.None;
        Rebuild(keepSelection: false);
    }

    public void SetQuery(string query)
    {
        if (query == Query) return;
        Query = query;
        ExpandedId = null;
        Rebuild(keepSelection: false);
    }

    public void SetFilter(PanelFilter filter)
    {
        if (filter == Filter) return;
        Filter = filter;
        ExpandedId = null;
        Rebuild(keepSelection: false);
    }

    public void NextFilter() => SetFilter(Filter.Next());
    public void PreviousFilter() => SetFilter(Filter.Previous());

    public void SetModifiers(ActionGrammar.Bits bits)
    {
        if (bits == Modifiers) return;
        Modifiers = bits;
        Version++;
    }

    public int CountFor(PanelFilter filter) =>
        _history.Concat(_sensitive).Count(r => filter.Matches(r.Kind));

    public void Select(Guid? id)
    {
        if (id == SelectedId) return;
        if (id is { } value && IndexOf(value) < 0) return;
        SelectedId = id;
        if (ExpandedId != id) ExpandedId = null;
        Version++;
    }

    /// <summary>Move without wrapping; collapses the preview.</summary>
    public void MoveSelection(int delta)
    {
        if (_visible.Count == 0) return;
        var index = SelectedIndex;
        var next = index < 0 ? (delta > 0 ? 0 : _visible.Count - 1) : Math.Clamp(index + delta, 0, _visible.Count - 1);
        ExpandedId = null;
        SelectedId = _visible[next].Id;
        Version++;
    }

    public void SelectFirst() => MoveSelection(int.MinValue / 2);
    public void SelectLast() => MoveSelection(int.MaxValue / 2);

    public PanelSections.Row? RowForNumber(int number) => _visible.FirstOrDefault(r => r.Number == number);

    public bool CanExpand => Selected is { } row && !row.Clip.IsSensitive && !row.Clip.IsGhost;

    public void ToggleExpand()
    {
        if (!CanExpand) return;
        ExpandedId = IsExpanded ? null : SelectedId;
        Version++;
    }

    public void Collapse()
    {
        if (ExpandedId is null) return;
        ExpandedId = null;
        Version++;
    }

    /// <summary>Which row should be selected after the current one is removed: the next, or the previous at the end.</summary>
    public Guid? SelectionAfterRemoving(Guid id)
    {
        var index = IndexOf(id);
        if (index < 0) return SelectedId;
        if (index + 1 < _visible.Count) return _visible[index + 1].Id;
        if (index - 1 >= 0) return _visible[index - 1].Id;
        return null;
    }

    private int IndexOf(Guid id)
    {
        for (var i = 0; i < _visible.Count; i++)
        {
            if (_visible[i].Id == id) return i;
        }
        return -1;
    }

    private void Rebuild(bool keepSelection)
    {
        var previous = SelectedId;
        var previousIndex = keepSelection ? SelectedIndex : -1;
        _sections = PanelSections.Build(_history, _sensitive, _ghosts, Filter, Query, Clock.Now, _timeZone);
        _visible = _sections.SelectMany(s => s.Rows).Where(r => !r.Clip.IsGhost).ToList();

        if (keepSelection && previous is { } id && IndexOf(id) >= 0)
        {
            SelectedId = id;
        }
        else if (keepSelection && previousIndex >= 0 && _visible.Count > 0)
        {
            SelectedId = _visible[Math.Min(previousIndex, _visible.Count - 1)].Id;
        }
        else
        {
            SelectedId = _visible.Count > 0 ? _visible[0].Id : null;
        }
        if (ExpandedId is not null && ExpandedId != SelectedId) ExpandedId = null;
        Version++;
    }
}
