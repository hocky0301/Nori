using Nori.Core;
using Xunit;
using Bits = Nori.Core.ActionGrammar.Bits;

namespace Nori.Core.Tests;

public class ActionGrammarTests
{
    [Fact]
    public void TruthTable()
    {
        var trusted = new ActionGrammar.Capabilities(CanPaste: true);
        var untrusted = new ActionGrammar.Capabilities(CanPaste: false);
        Assert.Equal(8, ActionGrammar.AllBits.Count);
        foreach (var bits in ActionGrammar.AllBits)
        {
            var plain = bits.HasFlag(Bits.Plain);
            var keepOpen = bits.HasFlag(Bits.KeepOpen);
            foreach (var @base in new[] { ActionGrammar.Base.Return, ActionGrammar.Base.Mouse })
            {
                var expected = bits.HasFlag(Bits.CopyOnly)
                    ? ActionGrammar.Action.Copy(plain, keepOpen)
                    : ActionGrammar.Action.Paste(plain, keepOpen);
                Assert.Equal(expected, ActionGrammar.Resolve(@base, bits, trusted));
                Assert.Equal(ActionGrammar.Action.Copy(plain, keepOpen), ActionGrammar.Resolve(@base, bits, untrusted));
            }
            // The number row is triggered by Ctrl, so Ctrl never means copy-only there.
            Assert.Equal(ActionGrammar.Action.Paste(plain, keepOpen), ActionGrammar.Resolve(new ActionGrammar.Base.Number(3), bits, trusted));
            Assert.Equal(ActionGrammar.Action.Copy(plain, keepOpen), ActionGrammar.Resolve(new ActionGrammar.Base.Number(3), bits, untrusted));
        }
    }

    [Fact]
    public void Verbs()
    {
        Assert.Equal("Paste", ActionGrammar.EnglishVerb(ActionGrammar.Action.Paste(false, false)));
        Assert.Equal("Paste plain, keep open", ActionGrammar.EnglishVerb(ActionGrammar.Action.Paste(true, true)));
        Assert.Equal("Copy as plain text", ActionGrammar.EnglishVerb(ActionGrammar.Action.Copy(true, false)));
        Assert.Equal("Verb_Paste", ActionGrammar.VerbKey(ActionGrammar.Action.Paste(false, false)));
        Assert.Equal("Verb_CopyKeepOpen", ActionGrammar.VerbKey(ActionGrammar.Action.Copy(false, true)));
        var keys = ActionGrammar.AllBits.Select(b => ActionGrammar.VerbKey(ActionGrammar.Resolve(ActionGrammar.Base.Return, b, new(true)))).ToHashSet();
        Assert.Equal(8, keys.Count);
    }

    [Fact]
    public void ModifierPrefixUsesTheWindowsOrder()
    {
        Assert.Equal("", ActionGrammar.ModifierPrefix(Bits.None));
        Assert.Equal("Ctrl+Alt+Shift+", ActionGrammar.ModifierPrefix(Bits.Plain | Bits.KeepOpen | Bits.CopyOnly));
        Assert.Equal("Shift+", ActionGrammar.ModifierPrefix(Bits.Plain));
        Assert.Equal(Bits.Plain | Bits.CopyOnly, ActionGrammar.FromModifiers(shift: true, alt: false, control: true));
    }
}

public class HintBarModelTests
{
    private static string[] Chips(Bits bits, bool canPaste = true, bool cycle = false, ClipKind? kind = ClipKind.Text) =>
        HintBarModel.Chips(new HintBarModel.Input(bits, canPaste, cycle, "Ctrl+Shift", kind, HasSelection: true))
            .Select(c => $"{c.Key} {c.VerbKey}").ToArray();

    [Fact]
    public void RestingStateHasFiveChips()
    {
        Assert.Equal(["Enter Verb_Paste", "Shift+Enter Hint_Plain", "Space Hint_Preview", "Ctrl+P Hint_Pin", "Del Hint_Delete"], Chips(Bits.None));
    }

    [Fact]
    public void ControlHeldShowsOpenOnlyForOpenableKinds()
    {
        Assert.Equal(
            ["Ctrl+1–9 Hint_PasteItem", "Ctrl+Enter Verb_Copy", "Ctrl+P Hint_Pin", "Ctrl+Y Hint_Preview", "Ctrl+Backspace Hint_Delete", "Ctrl+Shift+Backspace Hint_Clear"],
            Chips(Bits.CopyOnly, kind: ClipKind.Text));
        Assert.Contains("Ctrl+O Hint_Open", Chips(Bits.CopyOnly, kind: ClipKind.File));
        Assert.Contains("Ctrl+R Hint_Reveal", Chips(Bits.CopyOnly, kind: ClipKind.File));
        Assert.Contains("Ctrl+O Hint_Open", Chips(Bits.CopyOnly, kind: ClipKind.Link));
        Assert.Contains("Ctrl+O Hint_Open", Chips(Bits.CopyOnly, kind: ClipKind.Image));
        Assert.DoesNotContain("Ctrl+R Hint_Reveal", Chips(Bits.CopyOnly, kind: ClipKind.Link));
    }

    [Fact]
    public void ShiftAndAlt()
    {
        Assert.Equal(["Shift+Enter Verb_PastePlain", "Shift+click Hint_Same", "Ctrl+Shift+1–9 Hint_PasteItemPlain"], Chips(Bits.Plain));
        Assert.Equal(["Alt+Enter Verb_PasteKeepOpen", "Alt+click Hint_Same", "Ctrl+Alt+1–9 Hint_PasteItemKeepOpen"], Chips(Bits.KeepOpen));
        Assert.Equal(["Ctrl+Shift+Enter Verb_CopyPlain", "Ctrl+Shift+1–9 Hint_PasteItemPlain"], Chips(Bits.Plain | Bits.CopyOnly));
        Assert.Equal(["Ctrl+Alt+Enter Verb_CopyKeepOpen", "Ctrl+Alt+1–9 Hint_PasteItemKeepOpen"], Chips(Bits.KeepOpen | Bits.CopyOnly));
        Assert.Equal("Alt+Shift+Enter Verb_PastePlainKeepOpen", Chips(Bits.Plain | Bits.KeepOpen)[0]);
        Assert.Equal("Ctrl+Alt+Shift+1–9 Verb_PastePlainKeepOpen_Item", Chips(Bits.Plain | Bits.KeepOpen)[1]);
        Assert.Equal("Ctrl+Alt+Shift+Enter Verb_CopyPlainKeepOpen", Chips(Bits.Plain | Bits.KeepOpen | Bits.CopyOnly)[0]);
    }

    [Fact]
    public void NoPasteTargetTurnsPasteIntoCopy()
    {
        var resting = HintBarModel.Chips(new HintBarModel.Input(Bits.None, CanPaste: false, CycleMode: false, "Ctrl+Shift", ClipKind.Text, true));
        Assert.True(resting[0].IsWarning);
        Assert.Equal("Hint_CopyNoTarget", resting[0].VerbKey);
        Assert.Equal("Shift+Enter Verb_CopyPlain", Chips(Bits.Plain, canPaste: false)[0]);
        Assert.Equal("Ctrl+1–9 Hint_CopyItem", Chips(Bits.CopyOnly, canPaste: false)[0]);
    }

    [Fact]
    public void CycleMode()
    {
        Assert.Equal(["Release Ctrl+Shift Hint_ToPaste", "↑↓ Hint_Move", "Esc Hint_Cancel"], Chips(Bits.CopyOnly | Bits.Plain, cycle: true));
    }

    [Fact]
    public void EveryStateAgreesWithTheGrammar()
    {
        foreach (var bits in ActionGrammar.AllBits)
        {
            var chips = HintBarModel.Chips(new HintBarModel.Input(bits, true, false, "Ctrl+Shift", ClipKind.Text, true));
            var enter = Assert.Single(chips, c => c.Key == ActionGrammar.ModifierPrefix(bits) + "Enter");
            var action = ActionGrammar.Resolve(ActionGrammar.Base.Return, bits, new(true));
            var expectedKey = bits switch
            {
                Bits.None => "Verb_Paste",
                Bits.Plain => "Verb_PastePlain",
                Bits.KeepOpen => "Verb_PasteKeepOpen",
                Bits.CopyOnly => "Verb_Copy",
                Bits.Plain | Bits.CopyOnly => "Verb_CopyPlain",
                Bits.KeepOpen | Bits.CopyOnly => "Verb_CopyKeepOpen",
                _ => ActionGrammar.VerbKey(action),
            };
            Assert.Equal(expectedKey, enter.VerbKey);
            Assert.Equal(ActionGrammar.VerbKey(action), expectedKey);
        }
    }
}
