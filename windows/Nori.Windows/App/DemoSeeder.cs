using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Nori.Core;
using Nori.Windows.Clipboard;

namespace Nori.Windows;

/// <summary>
/// The demo history used by <c>--seed-demo</c> and the CI screenshots: the same set as the Mac
/// app's debug bridge (link, command, color, code, prose, email, rgb(), chat text, git command,
/// a pinned zenn.dev link, a drawn 1440×900 "window" PNG, a file, yesterday/earlier texts, one secret).
/// </summary>
internal static class DemoSeeder
{
    private sealed record DemoApp(string Exe, string Name, string? Path = null);

    private static readonly DemoApp Chrome = new("chrome.exe", "Google Chrome");
    private static readonly DemoApp Terminal = new("WindowsTerminal.exe", "Terminal");
    private static readonly DemoApp Figma = new("Figma.exe", "Figma");
    private static readonly DemoApp Code = new("Code.exe", "Visual Studio Code");
    private static readonly DemoApp Notepad = new("notepad.exe", "Notepad");
    private static readonly DemoApp Outlook = new("olk.exe", "Outlook");
    private static readonly DemoApp Slack = new("slack.exe", "Slack");
    private static readonly DemoApp Explorer = new("explorer.exe", "File Explorer", @"C:\Windows\explorer.exe");
    private static readonly DemoApp Snipping = new("SnippingTool.exe", "Snipping Tool");

    public static void Seed(HistoryStore history, SensitiveVault vault, DateTimeOffset now)
    {
        var samples = new List<ClipDraft>
        {
            Text("https://learn.microsoft.com/windows/apps/design/style/acrylic", Chrome),
            Text("winget install --id Nori.Nori", Terminal),
            Text("#5E5CE6", Figma),
            Text("public sealed record ClipRow\n{\n    public required Guid Id { get; init; }\n    public required ClipKind Kind { get; init; }\n}", Code),
            Text("Nori keeps the history of what you copy and lets you find it again in a keystroke. Everything stays on this PC.", Notepad),
            Text("kamil.ijuin@example.com", Outlook),
            Text("rgb(255, 122, 89)", Chrome),
            Text("Meeting moved to 15:30 — bring the Q3 numbers and the updated roadmap.", Slack),
            Text("git rebase -i HEAD~3", Terminal),
            Text("https://zenn.dev/", Chrome),
        };
        var time = now.AddHours(-1);
        samples.Reverse();
        foreach (var draft in samples)
        {
            history.Ingest(draft, time);
            time = time.AddMinutes(4);
        }
        // Yesterday and earlier, for the section headers.
        history.Ingest(Text("Yesterday's note: ship the README before the article.", Notepad), now.AddDays(-1));
        history.Ingest(Text("Three days ago: dotnet build windows/Nori.sln -c Release", Terminal), now.AddDays(-3));

        // A secret: masked, in memory only; captured two minutes ago so the card reads "Expires in 8m".
        var secret = Text("ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD", Chrome);
        vault.Add(new SensitiveDraft(SecretDetector.Match.GitHubToken, SecretDetector.Mask(secret.PlainText ?? string.Empty), secret), now.AddMinutes(-2));

        var png = DemoScreenshotPng();
        if (png is not null && ClipClassifier.MakeDraft([new ClipContent(ClipboardFormats.Png, png)], null, WpfImageNormalizer.Instance) is { } image)
        {
            image.SourceApp = Snipping.Exe;
            image.SourceAppName = Snipping.Name;
            history.Ingest(image, time);
        }
        if (ClipClassifier.MakeDraft([ClipDraft.File(@"C:\Windows\explorer.exe")]) is { } file)
        {
            file.SourceApp = Explorer.Exe;
            file.SourceAppName = Explorer.Name;
            file.SourceAppPath = Explorer.Path;
            history.Ingest(file, time.AddMinutes(1));
        }
        // The oldest of today's rows (zenn.dev) is pinned, so it sits first with Ctrl+1.
        var oldest = history.Rows.Where(r => r.LastCopiedAt >= now.AddHours(-1)).OrderBy(r => r.LastCopiedAt).FirstOrDefault();
        if (oldest is not null) history.TogglePin(oldest.Id, now.AddMinutes(-30));
    }

    /// <summary>The welcome clip inserted after onboarding (system clipboard untouched).</summary>
    public static void SeedWelcome(HistoryStore history, DateTimeOffset now)
    {
        var draft = ClipClassifier.MakeDraft([ClipDraft.Text(Resources.Strings.Get("Welcome_Seed"))]);
        if (draft is null) return;
        draft.SourceApp = "Nori.exe";
        draft.SourceAppName = Resources.Strings.Get("Source_Nori");
        history.Ingest(draft, now);
    }

    private static ClipDraft Text(string text, DemoApp app)
    {
        var draft = ClipClassifier.MakeDraft([ClipDraft.Text(text)], app.Exe, WpfImageNormalizer.Instance)!;
        draft.SourceApp = app.Exe;
        draft.SourceAppName = app.Name;
        draft.SourceAppPath = app.Path;
        return draft;
    }

    /// <summary>A 1440×900 mock "app window" over a gradient so image cards and previews look like a real screenshot.</summary>
    public static byte[]? DemoScreenshotPng()
    {
        try
        {
            const int width = 1440, height = 900;
            var visual = new DrawingVisual();
            using (var dc = visual.RenderOpen())
            {
                var gradient = new LinearGradientBrush(
                    [
                        new GradientStop(Color.FromRgb(0x2E, 0x33, 0x6B), 0),
                        new GradientStop(Color.FromRgb(0x8C, 0x4D, 0xAD), 0.5),
                        new GradientStop(Color.FromRgb(0xFA, 0x8C, 0x66), 1),
                    ],
                    new Point(0, 0), new Point(1, 1));
                dc.DrawRectangle(gradient, null, new Rect(0, 0, width, height));

                var window = new Rect(180, 140, 1080, 640);
                dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(235, 255, 255, 255)), null, window, 22, 22);
                dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(0xED, 0xED, 0xED)), null, new Rect(window.X, window.Y, window.Width, 52), 22, 22);
                dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0xED, 0xED, 0xED)), null, new Rect(window.X, window.Y + 30, window.Width, 22));
                var caption = new[] { Color.FromRgb(0xFF, 0x5F, 0x57), Color.FromRgb(0xFE, 0xBC, 0x2E), Color.FromRgb(0x28, 0xC8, 0x40) };
                for (var i = 0; i < caption.Length; i++)
                {
                    dc.DrawEllipse(new SolidColorBrush(caption[i]), null, new Point(window.X + 29 + i * 22, window.Y + 26), 7, 7);
                }
                var lines = new[] { 620, 840, 480, 760, 700, 300, 560 };
                var lineBrush = new SolidColorBrush(Color.FromRgb(0xD1, 0xD1, 0xD6));
                for (var i = 0; i < lines.Length; i++)
                {
                    dc.DrawRoundedRectangle(lineBrush, null, new Rect(window.X + 48, window.Y + 100 + i * 56, lines[i], 20), 10, 10);
                }
                dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(0x6B, 0x61, 0xFA)), null, new Rect(window.X + 48, window.Bottom - 92, 180, 44), 12, 12);
            }
            var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            bitmap.Freeze();
            return WpfImageNormalizer.EncodePng(bitmap);
        }
        catch (Exception e)
        {
            Log.Error("demo PNG could not be drawn", e);
            return null;
        }
    }
}
