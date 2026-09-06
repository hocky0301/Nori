using Nori.Core;
using Xunit;
using static Nori.Core.Tests.TestRows;

namespace Nori.Core.Tests;

public class ClipRowTests
{
    [Fact]
    public void DisplayTitleTakesTheFirstLineAndCollapsesWhitespace()
    {
        Assert.Equal("Meeting notes for today", Row("Meeting   notes\t\tfor   today\nsecond line").DisplayTitle);
        Assert.Equal("leading and trailing", Row("  leading and trailing  ").DisplayTitle);
        Assert.Equal("one", Row("one\r\ntwo").DisplayTitle);
        Assert.Equal("single", Row("single").DisplayTitle);
        Assert.Equal("a", Row("a\u2028b").DisplayTitle);
    }

    [Fact]
    public void DisplayTitleSkipsLeadingBlankLines()
    {
        Assert.Equal("second", Row("\nsecond").DisplayTitle);
        Assert.Equal("third", Row("\n\n  third  \nx").DisplayTitle);
        Assert.Equal("", Row("").DisplayTitle);
    }

    [Fact]
    public void CodeLinesExpandTabsAndSkipLeadingBlankLines()
    {
        Assert.Equal(["    if x {", "        return"], Row("\n   \n\tif x {\n\t\treturn\n\t}\n", ClipKind.Code).CodeLines);
    }

    [Fact]
    public void CodeLinesKeepLeadingSpacesAndStopAtTwo()
    {
        Assert.Equal(["  indented", "second"], Row("  indented\nsecond\nthird", ClipKind.Code).CodeLines);
        Assert.Equal(["only"], Row("only", ClipKind.Code).CodeLines);
        Assert.Equal(["first", ""], Row("first\n", ClipKind.Code).CodeLines);
    }

    [Fact]
    public void CodeLinesOfBlankTextAreTheOriginalLines()
    {
        Assert.Equal([""], Row("", ClipKind.Code).CodeLines);
        Assert.Equal(["  ", "    "], Row("  \n\t", ClipKind.Code).CodeLines);
    }

    [Fact]
    public void LinkHostStripsWwwOnly()
    {
        Assert.Equal("apple.com", Row("x", ClipKind.Link, link: "https://www.apple.com/design/").LinkHost);
        Assert.Equal("developer.apple.com", Row("x", ClipKind.Link, link: "https://developer.apple.com/").LinkHost);
        Assert.Equal("www2.example.org", Row("x", ClipKind.Link, link: "https://www2.example.org/").LinkHost);
        Assert.Null(Row("x", ClipKind.Link, link: "mailto:someone@example.com").LinkHost);
        Assert.Null(Row("plain").LinkHost);
    }

    [Fact]
    public void LinkPathAndQueryIsNullForTheRoot()
    {
        Assert.Null(Row("x", ClipKind.Link, link: "https://apple.com").LinkPathAndQuery);
        Assert.Null(Row("x", ClipKind.Link, link: "https://apple.com/").LinkPathAndQuery);
        Assert.Null(Row("x", ClipKind.Link, link: "https://apple.com/?").LinkPathAndQuery);
        Assert.Null(Row("plain").LinkPathAndQuery);
    }

    [Fact]
    public void LinkPathAndQueryKeepsPathAndQueryDecoded()
    {
        Assert.Equal("/design/human-interface-guidelines/liquid-glass",
            Row("x", ClipKind.Link, link: "https://developer.apple.com/design/human-interface-guidelines/liquid-glass").LinkPathAndQuery);
        Assert.Equal("/search?q=swift data&page=2", Row("x", ClipKind.Link, link: "https://example.com/search?q=swift%20data&page=2").LinkPathAndQuery);
        Assert.Equal("/?q=1", Row("x", ClipKind.Link, link: "https://example.com/?q=1").LinkPathAndQuery);
        Assert.Equal("/a/b", Row("x", ClipKind.Link, link: "https://example.com/a%2Fb").LinkPathAndQuery);
        Assert.Equal("/docs", Row("x", ClipKind.Link, link: "https://example.com/docs#section").LinkPathAndQuery);
    }

    [Fact]
    public void SourceFlags()
    {
        Assert.False(Row("x").IsPinned);
        Assert.True(Row("x", source: RowSource.Sensitive).IsSensitive);
        Assert.False(Row("x", source: RowSource.Sensitive).IsGhost);
        var ghost = ClipRow.Ghost(new GhostReason.Concealed("1Password"), T0);
        Assert.True(ghost.IsGhost);
        Assert.Equal("Concealed item from 1Password wasn't saved", ghost.Title);
        Assert.Equal(new GhostReason.Concealed("1Password"), ghost.GhostReason);
        Assert.Equal(ClipKind.Text, ghost.Kind);
        Assert.Equal("", ghost.SearchText);
        Assert.Equal(0, ghost.CopyCount);
        Assert.NotEqual(ClipRow.Ghost(new GhostReason.Concealed(null), T0).Id, ClipRow.Ghost(new GhostReason.Concealed(null), T0).Id);
        Assert.Equal("Concealed item from an app wasn't saved", ClipRow.Ghost(new GhostReason.Concealed(null), T0).Title);
    }

    [Fact]
    public void FileNamesAndFolders()
    {
        var row = Row("x", ClipKind.File) with { FilePaths = [@"C:\Users\me\Downloads\Invoice-2026-08.pdf", "/tmp/a/b.txt"] };
        Assert.Equal(["Invoice-2026-08.pdf", "b.txt"], row.FileNames);
        Assert.Equal(@"C:\Users\me\Downloads", ClipClassifier.ParentFolder(row.FilePaths[0]));
        Assert.Equal("/tmp/a", ClipClassifier.ParentFolder(row.FilePaths[1]));
        Assert.Equal("", ClipClassifier.ParentFolder("file.txt"));
    }

    [Fact]
    public void FilterCycling()
    {
        Assert.Equal(PanelFilter.Text, PanelFilter.All.Next());
        Assert.Equal(PanelFilter.All, PanelFilter.File.Next());
        Assert.Equal(PanelFilter.File, PanelFilter.All.Previous());
        Assert.True(PanelFilter.All.Matches(ClipKind.Image));
        Assert.True(PanelFilter.Code.Matches(ClipKind.Code));
        Assert.False(PanelFilter.Code.Matches(ClipKind.Text));
        Assert.Equal(7, PanelFilterExtensions.AllFilters.Count);
    }
}
