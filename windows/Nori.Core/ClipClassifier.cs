using System.Text;
using System.Text.RegularExpressions;

namespace Nori.Core;

/// <summary>
/// Turns a raw <see cref="ClipboardSnapshot"/> into a classified <see cref="ClipDraft"/>, a masked
/// sensitive draft, a ghost row, or a rejection. Pure and synchronous, so every rule is unit-tested
/// with hand-built snapshots.
/// </summary>
public static class ClipClassifier
{
    public static CaptureOutcome Classify(ClipboardSnapshot snapshot, CapturePolicy? policy = null, IImageNormalizer? normalizer = null)
    {
        policy ??= CapturePolicy.Default;
        normalizer ??= PngHeaderNormalizer.Instance;

        // 1. Nori's own write: the store bumps the existing item instead of re-capturing.
        if (snapshot.HasNoriMarker)
        {
            return new CaptureOutcome.Rejected(new CaptureRejection.FromNori(snapshot.NoriItemId));
        }

        // 2. Privacy markers are honoured wherever they appear (clipboard-level formats include
        //    formats that are on no item), so check the union.
        if (Declared(snapshot, ClipboardFormats.ExcludeFromMonitoring) || !snapshot.CanIncludeInHistory)
        {
            return new CaptureOutcome.Ghost(new GhostReason.Concealed(snapshot.SourceAppName ?? snapshot.SourceApp));
        }
        var ignoredFormat = snapshot.DeclaredFormats.FirstOrDefault(f => policy.IgnoredFormats.Contains(f));
        if (ignoredFormat is not null)
        {
            return new CaptureOutcome.Rejected(new CaptureRejection.IgnoredFormat(ignoredFormat));
        }
        if (snapshot.SourceApp is { } app && policy.IgnoredApps.Contains(app))
        {
            return new CaptureOutcome.Rejected(new CaptureRejection.IgnoredApp(app));
        }

        var regexes = policy.IgnoreRegexes.Select(TryRegex).Where(r => r is not null).Select(r => r!).ToList();

        // 3. Some apps put several data objects on the clipboard for one copy. Merge every
        //    representation into one draft, first item first, so a single history entry restores
        //    exactly what the app wrote.
        var merged = new List<ClipContent>();
        var seenFormats = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var matchedRegex = false;
        long? imageTooLarge = null;

        foreach (var item in snapshot.Items)
        {
            var text = item.String(ClipboardFormats.UnicodeText);
            if (text is not null && regexes.Count > 0 && regexes.Any(r => r.IsMatch(text)))
            {
                matchedRegex = true;
                continue;
            }

            var formats = item.Formats
                .Where(f => !ClipboardFormats.MetadataFormats.Contains(f)
                            && !ClipboardFormats.IgnoredPrefixes.Any(p => f.StartsWith(p, StringComparison.OrdinalIgnoreCase) && !ClipboardFormats.StableFormats.Contains(f)))
                .ToList();
            // Word bookmarks: keeping these makes Word paste a hyperlink to itself instead of the text.
            if (ClipboardFormats.MicrosoftLinkFormats.All(l => formats.Contains(l, StringComparer.OrdinalIgnoreCase)))
            {
                formats.RemoveAll(f => ClipboardFormats.MicrosoftLinkFormats.Contains(f));
            }
            if (!policy.CaptureText) formats.RemoveAll(ClipboardFormats.IsText);
            if (!policy.CaptureImages) formats.RemoveAll(ClipboardFormats.IsImage);
            if (!policy.CaptureFiles) formats.RemoveAll(f => ClipboardFormats.Is(f, ClipboardFormats.FileDrop));

            var allowed = new HashSet<string>(formats, StringComparer.OrdinalIgnoreCase);
            foreach (var (format, data) in item.Representations)
            {
                if (!allowed.Contains(format)) continue;
                // Files arrive as one representation per path: keep every one of them.
                var repeatable = ClipboardFormats.Is(format, ClipboardFormats.FileDrop);
                if (!repeatable && seenFormats.Contains(format)) continue;
                if (data is null) continue;
                if (repeatable)
                {
                    var file = new ClipContent(format, data);
                    if (!merged.Contains(file)) merged.Add(file);
                    seenFormats.Add(format);
                    continue;
                }

                // 4. Size caps. Images too large leave a ghost; other giant blobs are dropped without losing the clip.
                if (ClipboardFormats.IsImage(format))
                {
                    if (data.Length > policy.MaxImageBytes)
                    {
                        imageTooLarge = Math.Max(imageTooLarge ?? 0, data.Length);
                        continue;
                    }
                }
                else if (ClipboardFormats.IsText(format))
                {
                    // handled below (truncation)
                }
                else if (data.Length > policy.MaxOtherRepresentationBytes)
                {
                    continue;
                }
                seenFormats.Add(format);
                merged.Add(new ClipContent(format, data));
            }
        }

        if (imageTooLarge is { } tooLarge && !merged.Any(c => ClipboardFormats.IsImage(c.Format)))
        {
            // The image was the point of the copy (browsers add the alt text next to it).
            var onlyText = merged.All(c => ClipboardFormats.IsText(c.Format));
            if (merged.Count == 0 || onlyText)
            {
                return new CaptureOutcome.Ghost(new GhostReason.ImageTooLarge(tooLarge));
            }
        }

        if (merged.Count == 0)
        {
            return new CaptureOutcome.Rejected(matchedRegex ? new CaptureRejection.MatchedIgnoreRegex() : new CaptureRejection.NothingToStore());
        }

        var isTruncated = false;
        var textIndex = merged.FindIndex(c => ClipboardFormats.Is(c.Format, ClipboardFormats.UnicodeText));
        if (textIndex >= 0 && merged[textIndex].Data.Length > policy.MaxTextBytes)
        {
            var cut = Encoding.UTF8.GetString(merged[textIndex].Data, 0, policy.MaxTextBytes).TrimEnd('�');
            merged[textIndex] = new ClipContent(ClipboardFormats.UnicodeText, Encoding.UTF8.GetBytes(cut));
            merged.RemoveAll(c => ClipboardFormats.Is(c.Format, ClipboardFormats.Rtf) || ClipboardFormats.Is(c.Format, ClipboardFormats.Html));
            isTruncated = true;
        }

        var draft = MakeDraft(merged, snapshot.SourceApp, normalizer);
        if (draft is null)
        {
            return new CaptureOutcome.Rejected(new CaptureRejection.NothingToStore());
        }
        draft.SourceApp = snapshot.SourceApp;
        draft.SourceAppName = snapshot.SourceAppName;
        draft.SourceAppPath = snapshot.SourceAppPath;
        draft.IsTruncated = isTruncated;

        // 5. Secrets never touch disk.
        if (policy.MaskSensitive && draft.Kind.IsTextual() && draft.PlainText is { } plain && SecretDetector.Detect(plain) is { } match)
        {
            return new CaptureOutcome.Sensitive(new SensitiveDraft(match, SecretDetector.Mask(plain), draft));
        }
        return new CaptureOutcome.Captured(draft);
    }

    private static bool Declared(ClipboardSnapshot snapshot, string format) =>
        snapshot.DeclaredFormats.Any(f => ClipboardFormats.Is(f, format));

    private static Regex? TryRegex(string pattern)
    {
        try
        {
            return new Regex(pattern, RegexOptions.None, TimeSpan.FromMilliseconds(200));
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    // MARK: - Classification

    /// <summary>Builds a draft from representations that survived the capture rules. Null when there is nothing to show.</summary>
    public static ClipDraft? MakeDraft(IReadOnlyList<ClipContent> input, string? sourceApp = null, IImageNormalizer? normalizer = null)
    {
        normalizer ??= PngHeaderNormalizer.Instance;
        var contents = input.ToList();
        byte[]? Data(string format) => contents.FirstOrDefault(c => ClipboardFormats.Is(c.Format, format))?.Data;

        var filePaths = contents
            .Where(c => ClipboardFormats.Is(c.Format, ClipboardFormats.FileDrop))
            .Select(c => Encoding.UTF8.GetString(c.Data).Trim('\0', '\r', '\n'))
            .Where(p => p.Length > 0)
            .ToList();

        // Images: PNG only, plus an inline thumbnail.
        ImageResult? image = null;
        if (contents.Any(c => ClipboardFormats.IsImage(c.Format)))
        {
            image = normalizer.Normalize(contents);
            contents.RemoveAll(c => ClipboardFormats.IsImage(c.Format));
            if (image is not null)
            {
                contents.Insert(0, new ClipContent(ClipboardFormats.Png, image.Png));
            }
        }

        var plainBytes = Data(ClipboardFormats.UnicodeText);
        var plain = plainBytes is null ? null : Encoding.UTF8.GetString(plainBytes).TrimEnd('\0');
        var rich = RichTextString(Data(ClipboardFormats.Rtf), Data(ClipboardFormats.Html));
        var text = (!string.IsNullOrEmpty(plain) ? plain : rich) ?? string.Empty;

        var draft = new ClipDraft(contents, ContentHash.Of(contents));

        if (filePaths.Count > 0)
        {
            draft.Kind = ClipKind.File;
            draft.FilePaths = filePaths;
            var names = filePaths.Select(FileName).ToList();
            draft.Title = string.Join('\n', names);
            draft.SearchText = string.Join('\n', filePaths);
            draft.CharacterCount = draft.Title.Length;
            draft.LineCount = names.Count;
            return draft;
        }

        if (image is not null)
        {
            draft.Kind = ClipKind.Image;
            draft.ImagePixelSize = (image.Width, image.Height);
            draft.Thumbnail = image.Thumbnail;
            draft.Title = $"Image {image.Width}×{image.Height}";
            // Browsers put the page text / alt text next to the bitmap; keep it searchable.
            draft.SearchText = Truncate(text, ClipDraft.MaxSearchTextLength);
            return draft;
        }

        var trimmed = text.Trim();
        if (trimmed.Length == 0) return null;

        draft.CharacterCount = text.Length;
        draft.LineCount = KindDetector.SplitLines(trimmed).Count;
        draft.SearchText = Truncate(text, ClipDraft.MaxSearchTextLength);
        draft.Title = Truncate(trimmed, ClipDraft.MaxTitleLength);
        draft.IsRichText = RtfText.IsMeaningfullyRich(Data(ClipboardFormats.Rtf));

        if (KindDetector.Link(trimmed) is { } url)
        {
            draft.Kind = ClipKind.Link;
            draft.LinkUrl = url;
            draft.Title = url.OriginalString;
        }
        else if (KindDetector.Color(trimmed) is { } hex)
        {
            draft.Kind = ClipKind.Color;
            draft.ColorHex = hex;
            draft.Title = trimmed;
        }
        else if (KindDetector.LooksLikeCode(text, sourceApp, draft.IsRichText))
        {
            draft.Kind = ClipKind.Code;
        }
        else
        {
            draft.Kind = ClipKind.Text;
        }
        return draft;
    }

    public static string? RichTextString(byte[]? rtf, byte[]? html)
    {
        var fromRtf = RtfText.ToPlainText(rtf);
        if (!string.IsNullOrWhiteSpace(fromRtf)) return fromRtf;
        if (html is not null)
        {
            var fromHtml = HtmlFormat.ToPlainText(HtmlFormat.Fragment(html));
            if (!string.IsNullOrWhiteSpace(fromHtml)) return fromHtml;
        }
        return null;
    }

    /// <summary>Last path component, tolerant of both separators (paths are captured on Windows, tests run anywhere).</summary>
    public static string FileName(string path)
    {
        var trimmed = path.TrimEnd('\\', '/');
        var index = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
        return index >= 0 ? trimmed[(index + 1)..] : trimmed;
    }

    /// <summary>Parent folder of a path, with the same separator tolerance.</summary>
    public static string ParentFolder(string path)
    {
        var trimmed = path.TrimEnd('\\', '/');
        var index = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
        return index > 0 ? trimmed[..index] : string.Empty;
    }

    private static string Truncate(string text, int max) => text.Length <= max ? text : text[..max];
}
