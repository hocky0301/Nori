using System.Text;
using Nori.Core;
using Xunit;

namespace Nori.Core.Tests;

public class FormatTests
{
    [Fact]
    public void HtmlFormatRoundTrips()
    {
        var payload = HtmlFormat.Encode("<b>Hello</b> &amp; <i>bye</i>");
        var text = Encoding.UTF8.GetString(payload);
        Assert.StartsWith("Version:0.9\r\nStartHTML:", text);
        Assert.Equal("<b>Hello</b> &amp; <i>bye</i>", HtmlFormat.Fragment(payload));
        Assert.Equal("Hello & bye", HtmlFormat.ToPlainText(HtmlFormat.Fragment(payload)));
    }

    [Fact]
    public void HtmlOffsetsPointAtTheFragment()
    {
        var payload = HtmlFormat.Encode("<p>x</p>");
        var text = Encoding.UTF8.GetString(payload);
        var startFragment = int.Parse(text.Split("StartFragment:")[1][..10], System.Globalization.CultureInfo.InvariantCulture);
        var endFragment = int.Parse(text.Split("EndFragment:")[1][..10], System.Globalization.CultureInfo.InvariantCulture);
        Assert.Equal("<p>x</p>", Encoding.UTF8.GetString(payload, startFragment, endFragment - startFragment));
    }

    [Fact]
    public void HtmlToPlainTextStripsScriptsAndKeepsBreaks()
    {
        var html = "<style>p{}</style><script>alert(1)</script><p>One</p><p>Two<br>Three</p>";
        Assert.Equal("One\nTwo\nThree", HtmlFormat.ToPlainText(html));
        Assert.Equal("<html><body>x</body></html>", HtmlFormat.Fragment(Encoding.UTF8.GetBytes("Version:0.9\r\n<html><body>x</body></html>")));
    }

    [Fact]
    public void RtfPlainTextAndRichness()
    {
        var rich = Encoding.ASCII.GetBytes(@"{\rtf1\ansi{\fonttbl\f0\fswiss Helvetica;}\f0\fs24 \b Bold\b0  and plain\par second}");
        Assert.True(RtfText.IsMeaningfullyRich(rich));
        Assert.Equal("Bold and plain\nsecond", RtfText.ToPlainText(rich));
        var uniform = Encoding.ASCII.GetBytes(@"{\rtf1\ansi{\fonttbl\f0\fswiss Helvetica;}\f0\fs24 caf\'e9 \u12494?}");
        Assert.False(RtfText.IsMeaningfullyRich(uniform));
        Assert.Equal("café ノ", RtfText.ToPlainText(uniform));
        Assert.False(RtfText.IsMeaningfullyRich(null));
        Assert.Null(RtfText.ToPlainText(Encoding.ASCII.GetBytes("not rtf")));
        var twoSizes = Encoding.ASCII.GetBytes(@"{\rtf1\ansi\fs24 big\fs18 small}");
        Assert.True(RtfText.IsMeaningfullyRich(twoSizes));
    }

    [Fact]
    public void PngHeaderNormalizerReadsDimensions()
    {
        var png = PngHeaderNormalizer.SolidPng(1440, 900);
        Assert.Equal((1440, 900), PngHeaderNormalizer.PngSize(png));
        Assert.Null(PngHeaderNormalizer.PngSize(new byte[10]));
        var result = PngHeaderNormalizer.Instance.Normalize([new ClipContent(ClipboardFormats.Png, png)]);
        Assert.NotNull(result);
        Assert.Equal(1440, result.Width);
        Assert.Null(PngHeaderNormalizer.Instance.Normalize([new ClipContent(ClipboardFormats.Dib, new byte[40])]));
    }

    [Fact]
    public void SnapshotReadsTheNoriMarker()
    {
        var id = Guid.NewGuid();
        var snap = ClipboardSnapshot.Single([(ClipboardFormats.NoriItem, Encoding.UTF8.GetBytes(id.ToString() + "\0"))]);
        Assert.True(snap.HasNoriMarker);
        Assert.Equal(id, snap.NoriItemId);
        Assert.Null(ClipboardSnapshot.Single([(ClipboardFormats.NoriItem, Encoding.UTF8.GetBytes("junk"))]).NoriItemId);
    }

    [Fact]
    public void CapturePolicyDefaults()
    {
        var policy = CapturePolicy.Default;
        Assert.Contains("1Password.exe", policy.IgnoredApps);
        Assert.Contains("Clipboard Viewer Ignore", policy.IgnoredFormats);
        Assert.True(policy.CaptureText && policy.CaptureImages && policy.CaptureFiles && policy.MaskSensitive);
        Assert.Equal(10 * 1024 * 1024, policy.MaxImageBytes);
        Assert.Equal(2 * 1024 * 1024, policy.MaxTextBytes);
        Assert.Empty(policy.IgnoreRegexes);
    }
}
