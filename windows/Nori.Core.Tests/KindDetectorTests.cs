using Nori.Core;
using Xunit;

namespace Nori.Core.Tests;

public class KindDetectorTests
{
    [Theory]
    [InlineData("https://example.com/path?q=1")]
    [InlineData("http://localhost:3000")]
    [InlineData("mailto:someone@example.com")]
    [InlineData("  https://zenn.dev/articles/abc  ")]
    public void DetectsLinks(string text)
    {
        Assert.NotNull(KindDetector.Link(text.Trim()));
    }

    [Theory]
    [InlineData("hello world")]
    [InlineData("https://example.com and more")]
    [InlineData("example.com")]
    [InlineData("http://")]
    [InlineData("mailto:nobody")]
    [InlineData("file:///C:/Users/me/a.txt")]
    [InlineData("just: text")]
    public void RejectsNonLinks(string text)
    {
        Assert.Null(KindDetector.Link(text));
    }

    [Theory]
    [InlineData("#fff", "#FFFFFF")]
    [InlineData("#1a2B3c", "#1A2B3C")]
    [InlineData("#1a2B3c80", "#1A2B3C80")]
    [InlineData("#abcd", "#AABBCCDD")]
    [InlineData("rgb(255, 0, 128)", "#FF0080")]
    [InlineData("rgba(255, 0, 128, 0.5)", "#FF008080")]
    [InlineData("rgb(255 0 128 / 50%)", "#FF008080")]
    [InlineData("hsl(0, 100%, 50%)", "#FF0000")]
    [InlineData("hsl(120, 100%, 25%)", "#008000")]
    [InlineData("hsla(240, 100%, 50%, 1)", "#0000FF")]
    public void DetectsColors(string text, string expected)
    {
        Assert.Equal(expected, KindDetector.Color(text));
    }

    [Theory]
    [InlineData("#12")]
    [InlineData("#12345")]
    [InlineData("rgb(300,0,0)")]
    [InlineData("#ggg")]
    [InlineData("hsl(0,200%,50%)")]
    [InlineData("color: #fff;")]
    [InlineData("12345678")]
    public void RejectsNonColors(string text)
    {
        Assert.Null(KindDetector.Color(text));
    }

    [Fact]
    public void ColorCaptions()
    {
        Assert.Equal("rgb(255, 107, 53)", KindDetector.RgbText("#FF6B35"));
        Assert.Equal("hsl(16, 100%, 60%)", KindDetector.HslText("#FF6B35"));
        Assert.Equal("rgba(255, 0, 128, 0.5)", KindDetector.RgbText("#FF008080"));
        Assert.Equal((255, 107, 53, 255), KindDetector.Channels("#FF6B35"));
        Assert.Null(KindDetector.Channels("FF6B35"));
    }

    [Fact]
    public void DetectsSwiftCode()
    {
        const string code = "import Foundation\n\nstruct Point {\n    var x: Double\n    var y: Double\n}";
        Assert.True(KindDetector.LooksLikeCode(code));
    }

    [Fact]
    public void DetectsJavaScriptCode()
    {
        const string code = "const items = list.filter((item) => item.active);\nitems.forEach((item) => {\n  console.log(item.name);\n});";
        Assert.True(KindDetector.LooksLikeCode(code));
    }

    [Fact]
    public void DetectsShellCommands()
    {
        Assert.True(KindDetector.LooksLikeCode("brew install --cask maccy"));
        Assert.True(KindDetector.LooksLikeCode("git commit -m \"fix\""));
        Assert.True(KindDetector.LooksLikeCode("dotnet build windows/Nori.sln"));
        Assert.True(KindDetector.LooksLikeCode("winget install Nori.Nori"));
    }

    [Fact]
    public void ProseIsNotCode()
    {
        const string prose = "Nori keeps the history of what you copy and lets you find it again quickly.\n"
            + "It works with text, links, images and files; nothing ever leaves your PC.\n"
            + "Press the shortcut, type a few letters, hit return.";
        Assert.False(KindDetector.LooksLikeCode(prose));
        Assert.False(KindDetector.LooksLikeCode("Meet me at 5; bring the docs."));
        Assert.False(KindDetector.LooksLikeCode("Hello"));
    }

    [Fact]
    public void EditorSourceLowersTheBar()
    {
        const string source = "let a = 1\nlet b = 2\n";
        Assert.True(KindDetector.LooksLikeCode(source, "Code.exe"));
        Assert.True(KindDetector.LooksLikeCode(source, "com.apple.dt.Xcode"));
        Assert.False(KindDetector.LooksLikeCode(source, "notepad.exe"));
        Assert.False(KindDetector.LooksLikeCode(source, "Code.exe", isRichText: true));
    }

    [Fact]
    public void SplitLinesHandlesEveryTerminator()
    {
        Assert.Equal(["a", "b", "c", ""], KindDetector.SplitLines("a\r\nb\u2028c\n"));
        Assert.Equal([""], KindDetector.SplitLines(""));
    }
}
