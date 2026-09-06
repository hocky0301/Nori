using System.Text;
using Nori.Core;
using Xunit;

namespace Nori.Core.Tests;

public class ClipClassifierTests
{
    private static ClipboardSnapshot Snapshot(
        IReadOnlyList<IReadOnlyList<(string Format, byte[]? Data)>> items,
        IReadOnlySet<string>? declared = null,
        string? app = "notepad.exe",
        string? appName = "Notepad",
        bool canIncludeInHistory = true)
    {
        var built = items.Select(i => new ClipboardSnapshot.Item(i)).ToList();
        var declaredFormats = declared ?? new HashSet<string>(built.SelectMany(i => i.Formats), StringComparer.OrdinalIgnoreCase);
        return new ClipboardSnapshot(declaredFormats, built, app, appName, canIncludeInHistory: canIncludeInHistory);
    }

    private static (string, byte[]?) Text(string s) => (ClipboardFormats.UnicodeText, Encoding.UTF8.GetBytes(s));

    private static ClipDraft Draft(CaptureOutcome outcome)
    {
        var captured = Assert.IsType<CaptureOutcome.Captured>(outcome);
        return captured.Draft;
    }

    [Fact]
    public void PlainText()
    {
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text("  Hello, Nori!\n")]])));
        Assert.Equal(ClipKind.Text, draft.Kind);
        Assert.Equal("Hello, Nori!", draft.Title);
        Assert.Equal("  Hello, Nori!\n", draft.SearchText);
        Assert.Equal(15, draft.CharacterCount);
        Assert.Equal(1, draft.LineCount);
        Assert.Equal("notepad.exe", draft.SourceApp);
        Assert.Equal("Notepad", draft.SourceAppName);
        Assert.Single(draft.Contents);
        Assert.False(draft.IsRichText);
    }

    [Fact]
    public void Link()
    {
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text("https://maccy.app/\n")]])));
        Assert.Equal(ClipKind.Link, draft.Kind);
        Assert.Equal("maccy.app", draft.LinkUrl?.Host);
    }

    [Fact]
    public void Color()
    {
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text("#ff8800")]])));
        Assert.Equal(ClipKind.Color, draft.Kind);
        Assert.Equal("#FF8800", draft.ColorHex);
    }

    [Fact]
    public void Code()
    {
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text("func hello() {\n    print(\"hi\")\n}\n")]])));
        Assert.Equal(ClipKind.Code, draft.Kind);
    }

    [Fact]
    public void CodeFromEditorNeedsLessEvidence()
    {
        const string source = "let a = 1\nlet b = 2\n";
        Assert.Equal(ClipKind.Code, Draft(ClipClassifier.Classify(Snapshot([[Text(source)]], app: "Code.exe"))).Kind);
        Assert.Equal(ClipKind.Text, Draft(ClipClassifier.Classify(Snapshot([[Text(source)]], app: "notepad.exe"))).Kind);
    }

    [Fact]
    public void RichTextIsAFlagOnText()
    {
        var rtf = Encoding.ASCII.GetBytes(@"{\rtf1\ansi{\fonttbl\f0\fswiss Helvetica;}\f0\fs24 \b Bold\b0  and plain}");
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text("Bold and plain"), (ClipboardFormats.Rtf, rtf)]])));
        Assert.Equal(ClipKind.Text, draft.Kind);
        Assert.True(draft.IsRichText);
        Assert.Equal("Bold and plain", draft.Title);
        Assert.Equal([ClipboardFormats.UnicodeText, ClipboardFormats.Rtf], draft.Contents.Select(c => c.Format));
    }

    [Fact]
    public void UniformRtfIsNotRich()
    {
        var rtf = Encoding.ASCII.GetBytes(@"{\rtf1\ansi{\fonttbl\f0\fswiss Helvetica;}\f0\fs24 just text}");
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text("just text"), (ClipboardFormats.Rtf, rtf)]])));
        Assert.False(draft.IsRichText);
    }

    [Fact]
    public void HtmlAloneNeverMakesAClipRich()
    {
        var html = HtmlFormat.Encode("<b>bold</b> text");
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text("bold text"), (ClipboardFormats.Html, html)]])));
        Assert.False(draft.IsRichText);
        Assert.Equal(2, draft.Contents.Count);
    }

    [Fact]
    public void ImageKeepsPngOnlyAndReadsSize()
    {
        var png = PngHeaderNormalizer.SolidPng(300, 120);
        var dib = new byte[64];
        var draft = Draft(ClipClassifier.Classify(Snapshot([[(ClipboardFormats.Dib, dib), (ClipboardFormats.Png, png), Text("alt text")]])));
        Assert.Equal(ClipKind.Image, draft.Kind);
        Assert.Equal((300, 120), draft.ImagePixelSize);
        Assert.Equal("Image 300×120", draft.Title);
        Assert.Equal("alt text", draft.SearchText);
        Assert.Equal([ClipboardFormats.Png, ClipboardFormats.UnicodeText], draft.Contents.Select(c => c.Format));
    }

    private sealed class StubNormalizer : IImageNormalizer
    {
        public ImageResult? Normalize(IReadOnlyList<ClipContent> contents) =>
            new(PngHeaderNormalizer.SolidPng(40, 30), 40, 30, PngHeaderNormalizer.SolidPng(20, 15));
    }

    [Fact]
    public void DibOnlyIsTranscodedByTheNormalizer()
    {
        var draft = Draft(ClipClassifier.Classify(Snapshot([[(ClipboardFormats.Dib, new byte[64])]]), normalizer: new StubNormalizer()));
        Assert.Equal([ClipboardFormats.Png], draft.Contents.Select(c => c.Format));
        Assert.Equal((40, 30), draft.ImagePixelSize);
        Assert.NotNull(draft.Thumbnail);
        Assert.Equal((20, 15), PngHeaderNormalizer.PngSize(draft.Thumbnail));
    }

    [Fact]
    public void Files()
    {
        var snap = Snapshot([
            [ClipDraft.File(@"C:\Users\me\Documents\My File.txt").ToTuple(), Text("My File.txt")],
            [ClipDraft.File(@"C:\tmp\other.pdf").ToTuple(), Text("other.pdf")],
        ]);
        var draft = Draft(ClipClassifier.Classify(snap));
        Assert.Equal(ClipKind.File, draft.Kind);
        Assert.Equal(["My File.txt", "other.pdf"], draft.FilePaths.Select(ClipClassifier.FileName));
        Assert.Equal("My File.txt\nother.pdf", draft.Title);
        Assert.Equal(2, draft.LineCount);
        Assert.Equal(@"C:\Users\me\Documents", ClipClassifier.ParentFolder(draft.FilePaths[0]));
    }

    [Fact]
    public void MergesMultipleItemsWithoutDuplicatingFormats()
    {
        var snap = Snapshot([[Text("one")], [Text("two"), (ClipboardFormats.Html, HtmlFormat.Encode("<b>two</b>"))]]);
        var draft = Draft(ClipClassifier.Classify(snap));
        Assert.Equal([ClipboardFormats.UnicodeText, ClipboardFormats.Html], draft.Contents.Select(c => c.Format));
        Assert.Equal("one", draft.Title);
    }

    [Fact]
    public void WhitespaceOnlyIsRejected()
    {
        var outcome = ClipClassifier.Classify(Snapshot([[Text("   \n\t")]]));
        var rejected = Assert.IsType<CaptureOutcome.Rejected>(outcome);
        Assert.IsType<CaptureRejection.NothingToStore>(rejected.Rejection);
    }

    [Fact]
    public void MissingDataIsRejected()
    {
        var outcome = ClipClassifier.Classify(Snapshot([[(ClipboardFormats.UnicodeText, null)]]));
        Assert.IsType<CaptureRejection.NothingToStore>(Assert.IsType<CaptureOutcome.Rejected>(outcome).Rejection);
    }

    [Fact]
    public void ConcealedLeavesAGhostEvenWhenOnlyDeclared()
    {
        var declared = new HashSet<string>([ClipboardFormats.UnicodeText, ClipboardFormats.ExcludeFromMonitoring], StringComparer.OrdinalIgnoreCase);
        var snap = Snapshot([[Text("hunter2")]], declared, app: "1Password.exe", appName: "1Password");
        var ghost = Assert.IsType<CaptureOutcome.Ghost>(ClipClassifier.Classify(snap));
        Assert.Equal(new GhostReason.Concealed("1Password"), ghost.Reason);
    }

    [Fact]
    public void CanIncludeInHistoryZeroIsConcealed()
    {
        var snap = Snapshot([[Text("otp 123456")]], canIncludeInHistory: false, appName: "Authenticator");
        var ghost = Assert.IsType<CaptureOutcome.Ghost>(ClipClassifier.Classify(snap));
        Assert.Equal(new GhostReason.Concealed("Authenticator"), ghost.Reason);
    }

    [Fact]
    public void IgnoredCustomFormats()
    {
        var snap = Snapshot([[Text("secret"), ("Clipboard Viewer Ignore", Array.Empty<byte>())]]);
        var rejected = Assert.IsType<CaptureOutcome.Rejected>(ClipClassifier.Classify(snap));
        Assert.Equal(new CaptureRejection.IgnoredFormat("Clipboard Viewer Ignore"), rejected.Rejection);
    }

    [Fact]
    public void IgnoredAppsIncludePasswordManagersByDefault()
    {
        var snap = Snapshot([[Text("pw")]], app: "KeePassXC.exe");
        var rejected = Assert.IsType<CaptureOutcome.Rejected>(ClipClassifier.Classify(snap));
        Assert.Equal(new CaptureRejection.IgnoredApp("KeePassXC.exe"), rejected.Rejection);
        // Exe names are compared case-insensitively.
        Assert.IsType<CaptureOutcome.Rejected>(ClipClassifier.Classify(Snapshot([[Text("pw")]], app: "bitwarden.exe")));
    }

    [Fact]
    public void IgnoreRegex()
    {
        var policy = CapturePolicy.Default with { IgnoreRegexes = ["^order-[0-9]{6}$"] };
        var rejected = Assert.IsType<CaptureOutcome.Rejected>(ClipClassifier.Classify(Snapshot([[Text("order-123456")]]), policy));
        Assert.IsType<CaptureRejection.MatchedIgnoreRegex>(rejected.Rejection);
        Assert.IsType<CaptureOutcome.Captured>(ClipClassifier.Classify(Snapshot([[Text("order-12")]]), policy));
        // Invalid patterns are ignored rather than breaking capture.
        var broken = CapturePolicy.Default with { IgnoreRegexes = ["("] };
        Assert.IsType<CaptureOutcome.Captured>(ClipClassifier.Classify(Snapshot([[Text("order-12")]]), broken));
    }

    [Fact]
    public void FromNoriIsRejectedWithId()
    {
        var id = Guid.NewGuid();
        var snap = Snapshot([[Text("again"), (ClipboardFormats.NoriItem, Encoding.UTF8.GetBytes(id.ToString()))]]);
        var rejected = Assert.IsType<CaptureOutcome.Rejected>(ClipClassifier.Classify(snap));
        Assert.Equal(new CaptureRejection.FromNori(id), rejected.Rejection);
    }

    [Fact]
    public void DropsDynamicAndMetadataFormats()
    {
        var snap = Snapshot([[
            Text("hello"),
            ("Format123", new byte[] { 1 }),
            ("Embed Source", new byte[] { 2 }),
            ("Chromium Web Custom MIME Data Format", new byte[] { 3 }),
            ("Locale", new byte[] { 4 }),
        ]]);
        var draft = Draft(ClipClassifier.Classify(snap));
        Assert.Equal([ClipboardFormats.UnicodeText], draft.Contents.Select(c => c.Format));
    }

    [Fact]
    public void StripsWordLinkFormats()
    {
        var rtf = Encoding.ASCII.GetBytes(@"{\rtf1 Heading 1}");
        var snap = Snapshot([[
            Text("Heading 1"),
            ("ObjectLink", new byte[] { 1 }),
            ("Link Source", new byte[] { 2 }),
            (ClipboardFormats.Rtf, rtf),
        ]]);
        var draft = Draft(ClipClassifier.Classify(snap));
        Assert.DoesNotContain(draft.Contents, c => c.Format is "ObjectLink" or "Link Source");
        Assert.Contains(draft.Contents, c => c.Format == ClipboardFormats.Rtf);
    }

    [Fact]
    public void PolicyCanDisableImagesFilesAndText()
    {
        var policy = CapturePolicy.Default with { CaptureImages = false, CaptureFiles = false };
        var png = PngHeaderNormalizer.SolidPng(2, 2);
        var snap = Snapshot([[(ClipboardFormats.Png, png), (ClipboardFormats.Rtf, new byte[] { 1 }), Text("caption")]]);
        var draft = Draft(ClipClassifier.Classify(snap, policy));
        Assert.Equal(ClipKind.Text, draft.Kind);
        Assert.Equal([ClipboardFormats.Rtf, ClipboardFormats.UnicodeText], draft.Contents.Select(c => c.Format));

        var noText = policy with { CaptureText = false };
        var rejected = Assert.IsType<CaptureOutcome.Rejected>(ClipClassifier.Classify(Snapshot([[Text("caption")]]), noText));
        Assert.IsType<CaptureRejection.NothingToStore>(rejected.Rejection);
    }

    [Fact]
    public void OversizedImageLeavesAGhost()
    {
        var policy = CapturePolicy.Default with { MaxImageBytes = 4 };
        var png = PngHeaderNormalizer.SolidPng(2, 2);
        var outcome = ClipClassifier.Classify(Snapshot([[(ClipboardFormats.Png, png), Text("alt")]]), policy);
        var ghost = Assert.IsType<CaptureOutcome.Ghost>(outcome);
        Assert.Equal(new GhostReason.ImageTooLarge(png.Length), ghost.Reason);
    }

    [Fact]
    public void OversizedOtherRepresentationIsDroppedButClipKept()
    {
        var policy = CapturePolicy.Default with { MaxOtherRepresentationBytes = 4 };
        var snap = Snapshot([[Text("tiny"), ("Some.Custom.Format", new byte[10]), ("Another", new byte[10])]]);
        var draft = Draft(ClipClassifier.Classify(snap, policy));
        Assert.Equal([ClipboardFormats.UnicodeText], draft.Contents.Select(c => c.Format));
    }

    [Fact]
    public void HugeTextIsTruncated()
    {
        var policy = CapturePolicy.Default with { MaxTextBytes = 16 };
        var snap = Snapshot([[Text(new string('a', 100)), (ClipboardFormats.Rtf, new byte[] { 1 })]]);
        var draft = Draft(ClipClassifier.Classify(snap, policy));
        Assert.True(draft.IsTruncated);
        Assert.Equal(16, draft.CharacterCount);
        Assert.Equal([ClipboardFormats.UnicodeText], draft.Contents.Select(c => c.Format));
    }

    [Fact]
    public void SecretsGoToTheVault()
    {
        var outcome = ClipClassifier.Classify(Snapshot([[Text("AKIAIOSFODNN7EXAMPLE")]]));
        var sensitive = Assert.IsType<CaptureOutcome.Sensitive>(outcome);
        Assert.Equal(SecretDetector.Match.AwsAccessKey, sensitive.Draft.Match);
        Assert.EndsWith("MPLE", sensitive.Draft.Mask);
        Assert.DoesNotContain("AKIA", sensitive.Draft.Mask);

        var policy = CapturePolicy.Default with { MaskSensitive = false };
        Assert.Equal(ClipKind.Text, Draft(ClipClassifier.Classify(Snapshot([[Text("AKIAIOSFODNN7EXAMPLE")]]), policy)).Kind);
    }

    [Fact]
    public void HashIgnoresCustomFormatsButNotContent()
    {
        var a = new List<ClipContent> { ClipDraft.Text("x"), new("Some.Custom", [9]) };
        var b = new List<ClipContent> { ClipDraft.Text("x") };
        var c = new List<ClipContent> { ClipDraft.Text("y") };
        Assert.Equal(ContentHash.Of(a), ContentHash.Of(b));
        Assert.NotEqual(ContentHash.Of(a), ContentHash.Of(c));
    }

    [Fact]
    public void HashIsOrderIndependentAndDistinguishesRich()
    {
        var html = new ClipContent(ClipboardFormats.Html, HtmlFormat.Encode("x"));
        var a = new List<ClipContent> { ClipDraft.Text("x"), html };
        var b = new List<ClipContent> { html, ClipDraft.Text("x") };
        var plain = new List<ClipContent> { ClipDraft.Text("x") };
        Assert.Equal(ContentHash.Of(a), ContentHash.Of(b));
        Assert.NotEqual(ContentHash.Of(a), ContentHash.Of(plain));
        Assert.Equal(64, ContentHash.Of(plain).Length);
    }

    [Fact]
    public void LongTextIsTruncatedForTitleAndSearch()
    {
        var draft = Draft(ClipClassifier.Classify(Snapshot([[Text(new string('a', 20_000))]])));
        Assert.Equal(ClipDraft.MaxTitleLength, draft.Title.Length);
        Assert.Equal(ClipDraft.MaxSearchTextLength, draft.SearchText.Length);
        Assert.Equal(20_000, draft.CharacterCount);
    }

    [Fact]
    public void HtmlOnlyCopyUsesTheHtmlText()
    {
        var html = HtmlFormat.Encode("<p>Hello <b>world</b></p><p>Second</p>");
        var draft = Draft(ClipClassifier.Classify(Snapshot([[(ClipboardFormats.Html, html)]])));
        Assert.Equal(ClipKind.Text, draft.Kind);
        Assert.Equal("Hello world\nSecond", draft.Title);
    }
}

internal static class ClipContentExtensions
{
    public static (string, byte[]?) ToTuple(this ClipContent content) => (content.Format, content.Data);
}
