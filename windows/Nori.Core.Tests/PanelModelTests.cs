using Nori.Core;
using Xunit;
using static Nori.Core.Tests.TestRows;

namespace Nori.Core.Tests;

public class PanelModelTests
{
    private static PanelModel Model(IReadOnlyList<ClipRow>? history = null, IReadOnlyList<ClipRow>? sensitive = null, IReadOnlyList<ClipRow>? ghosts = null)
    {
        var model = new PanelModel(new FixedClock(T0), Utc);
        model.SetRows(history ?? [], sensitive ?? [], ghosts ?? []);
        model.Open();
        return model;
    }

    private static List<ClipRow> Seed() =>
    [
        Row("https://zenn.dev/", ClipKind.Link, at: T0.AddMinutes(-40), pinnedAt: T0.AddMinutes(-1), link: "https://zenn.dev/"),
        Row("git rebase -i HEAD~3", ClipKind.Code, at: T0.AddMinutes(-2)),
        Row("#5E5CE6", ClipKind.Color, at: T0.AddMinutes(-5)),
        Row("Meeting moved to 15:30", at: T0.AddMinutes(-9)),
        Row("Yesterday's note", at: T0.AddDays(-1)),
    ];

    [Fact]
    public void OpenResetsStateAndSelectsTheFirstRow()
    {
        var model = Model(Seed());
        model.SetQuery("meeting");
        model.SetFilter(PanelFilter.Text);
        model.SetModifiers(ActionGrammar.Bits.CopyOnly);
        model.Open();
        Assert.Equal("", model.Query);
        Assert.Equal(PanelFilter.All, model.Filter);
        Assert.Equal(ActionGrammar.Bits.None, model.Modifiers);
        Assert.Equal("https://zenn.dev/", model.Selected!.Clip.Title);
        Assert.Equal(1, model.Selected.Number);
        Assert.Equal(5, model.VisibleRows.Count);
        Assert.Equal(EmptyState.None, model.EmptyState);
    }

    [Fact]
    public void SelectionMovesWithoutWrapping()
    {
        var model = Model(Seed());
        model.MoveSelection(-1);
        Assert.Equal(0, model.SelectedIndex);
        model.MoveSelection(1);
        Assert.Equal(1, model.SelectedIndex);
        model.SelectLast();
        Assert.Equal(4, model.SelectedIndex);
        model.MoveSelection(1);
        Assert.Equal(4, model.SelectedIndex);
        model.SelectFirst();
        Assert.Equal(0, model.SelectedIndex);
        model.MoveSelection(3);
        Assert.Equal(3, model.SelectedIndex);
    }

    [Fact]
    public void GhostRowsAreNeverSelectable()
    {
        var ghost = ClipRow.Ghost(new GhostReason.Concealed("1Password"), T0);
        var model = Model([Row("a", at: T0.AddMinutes(-1))], ghosts: [ghost]);
        Assert.Equal(2, model.Sections[0].Rows.Count);
        Assert.Single(model.VisibleRows);
        Assert.Equal("a", model.Selected!.Clip.Title);
        model.Select(ghost.Id);
        Assert.Equal("a", model.Selected!.Clip.Title);
    }

    [Fact]
    public void QueryAndFilterRebuildAndReselect()
    {
        var model = Model(Seed());
        model.SetQuery("note");
        Assert.True(model.IsSearching);
        Assert.Equal([SectionKind.Results], model.Sections.Select(s => s.Kind));
        Assert.Equal("Yesterday's note", model.Selected!.Clip.Title);
        model.SetQuery("nothing here");
        Assert.Null(model.Selected);
        Assert.Equal(EmptyState.NoMatches, model.EmptyState);
        Assert.True(model.ShouldPasteTypedText);
        model.SetQuery("");
        model.SetFilter(PanelFilter.Image);
        Assert.Equal(EmptyState.FilterEmpty, model.EmptyState);
        Assert.False(model.ShouldPasteTypedText);
        model.NextFilter();
        Assert.Equal(PanelFilter.File, model.Filter);
        model.NextFilter();
        Assert.Equal(PanelFilter.All, model.Filter);
        model.PreviousFilter();
        Assert.Equal(PanelFilter.File, model.Filter);
        Assert.Equal(1, model.CountFor(PanelFilter.Link));
        Assert.Equal(0, model.CountFor(PanelFilter.Image));
    }

    [Fact]
    public void EmptyHistoryIsNothingCopied()
    {
        var model = Model();
        Assert.Equal(EmptyState.NothingCopied, model.EmptyState);
        model.SetQuery("x");
        Assert.Equal(EmptyState.NothingCopied, model.EmptyState);
        Assert.True(model.ShouldPasteTypedText);
    }

    [Fact]
    public void ExpandOnlyForNormalRowsAndCollapsesOnMove()
    {
        var secret = Row("•••• 1111", source: RowSource.Sensitive) with { SearchText = "" };
        var model = Model([Row("a", at: T0.AddMinutes(-1))], [secret]);
        Assert.Equal("•••• 1111", model.Selected!.Clip.Title);
        Assert.False(model.CanExpand);
        model.ToggleExpand();
        Assert.False(model.IsExpanded);
        model.MoveSelection(1);
        Assert.True(model.CanExpand);
        model.ToggleExpand();
        Assert.True(model.IsExpanded);
        model.ToggleExpand();
        Assert.False(model.IsExpanded);
        model.ToggleExpand();
        model.MoveSelection(-1);
        Assert.False(model.IsExpanded);
        Assert.Null(model.ExpandedId);
    }

    [Fact]
    public void NumbersMapToVisibleRows()
    {
        var model = Model(Seed());
        Assert.Equal("git rebase -i HEAD~3", model.RowForNumber(2)!.Clip.Title);
        Assert.Null(model.RowForNumber(9));
    }

    [Fact]
    public void SelectionAfterDeleteMovesToNextOrPrevious()
    {
        var model = Model(Seed());
        var first = model.VisibleRows[0].Id;
        Assert.Equal(model.VisibleRows[1].Id, model.SelectionAfterRemoving(first));
        var last = model.VisibleRows[^1].Id;
        Assert.Equal(model.VisibleRows[^2].Id, model.SelectionAfterRemoving(last));
        var solo = Model([Row("only")]);
        Assert.Null(solo.SelectionAfterRemoving(solo.VisibleRows[0].Id));
    }

    [Fact]
    public void SetRowsKeepsTheSelectionWhenItStillExistsOrFallsBackToTheSameIndex()
    {
        var rows = Seed();
        var model = Model(rows);
        model.MoveSelection(2);
        var selected = model.SelectedId;
        var withNew = rows.Append(Row("new", at: T0)).ToList();
        model.SetRows(withNew, [], []);
        Assert.Equal(selected, model.SelectedId);
        Assert.Equal(3, model.SelectedIndex);
        // The deleted row was at index 3; the row that slid into its place is selected.
        model.SetRows(withNew.Where(r => r.Id != selected).ToList(), [], []);
        Assert.Equal(3, model.SelectedIndex);
        Assert.Equal("Meeting moved to 15:30", model.Selected!.Clip.Title);
        Assert.NotEqual(selected, model.SelectedId);
    }

    [Fact]
    public void VersionBumpsOnVisibleChanges()
    {
        var model = Model(Seed());
        var version = model.Version;
        model.SetModifiers(ActionGrammar.Bits.Plain);
        Assert.Equal(version + 1, model.Version);
        model.SetModifiers(ActionGrammar.Bits.Plain);
        Assert.Equal(version + 1, model.Version);
        model.Select(model.SelectedId);
        Assert.Equal(version + 1, model.Version);
    }
}

public class PanelPlacementTests
{
    private static readonly PanelRect Work = new(0, 0, 1920, 1040);

    [Fact]
    public void HeightIsThreeQuartersClamped()
    {
        Assert.Equal(620, PanelPlacement.Height(Work));
        Assert.Equal(320, PanelPlacement.Height(new PanelRect(0, 0, 800, 300)));
        Assert.Equal(525, PanelPlacement.Height(new PanelRect(0, 0, 1280, 700)));
    }

    [Fact]
    public void CursorModeClampsIntoTheWorkArea()
    {
        var rect = PanelPlacement.Compute(PanelPosition.Cursor, Work, 100, 200);
        Assert.Equal(new PanelRect(100, 200, 560, 620), rect);
        var clamped = PanelPlacement.Compute(PanelPosition.Cursor, Work, 1800, 900);
        Assert.Equal(new PanelRect(1360, 420, 560, 620), clamped);
        var offset = PanelPlacement.Compute(PanelPosition.Cursor, new PanelRect(-1920, 0, 1920, 1040), -1910, 10);
        Assert.Equal(-1910, offset.X);
    }

    [Fact]
    public void CenterAndTrayModes()
    {
        var center = PanelPlacement.Compute(PanelPosition.Center, Work, 0, 0);
        Assert.Equal(680, center.X);
        Assert.Equal(228, center.Y);
        var tray = PanelPlacement.Compute(PanelPosition.Tray, Work, 0, 0);
        Assert.Equal(1920 - 560 - 12, tray.X);
        Assert.Equal(1040 - 620 - 12, tray.Y);
    }
}
