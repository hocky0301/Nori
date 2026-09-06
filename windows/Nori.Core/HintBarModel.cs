namespace Nori.Core;

/// <summary>
/// What the hint bar shows for the current modifier state. Pure, so it is tested as a table and can
/// never disagree with <see cref="ActionGrammar"/>. Keys are Windows key names; verbs are resource keys.
/// </summary>
public static class HintBarModel
{
    /// <param name="Key">Keycap text, e.g. "Enter", "Shift+Enter", "Ctrl+1–9".</param>
    /// <param name="VerbKey">Resource key of the verb, e.g. "Verb_Paste", "Hint_Preview".</param>
    /// <param name="IsWarning">True for the chip that explains why Enter copies instead of pasting.</param>
    public sealed record Chip(string Key, string VerbKey, bool IsWarning = false)
    {
        public override string ToString() => $"{Key} {VerbKey}";
    }

    public sealed record Input(
        ActionGrammar.Bits Bits,
        bool CanPaste,
        bool CycleMode,
        // The hotkey's modifier text (for cycle mode), e.g. "Ctrl+Shift".
        string HotkeyModifiers,
        ClipKind? SelectedKind,
        bool HasSelection);

    public const string NumberRow = "1–9";

    public static IReadOnlyList<Chip> Chips(Input input)
    {
        if (input.CycleMode)
        {
            return
            [
                new Chip($"Release {input.HotkeyModifiers}", "Hint_ToPaste"),
                new Chip("↑↓", "Hint_Move"),
                new Chip("Esc", "Hint_Cancel"),
            ];
        }

        var caps = new ActionGrammar.Capabilities(input.CanPaste);
        var itemVerb = input.CanPaste ? "Hint_PasteItem" : "Hint_CopyItem";
        var itemPlain = input.CanPaste ? "Hint_PasteItemPlain" : "Hint_CopyItemPlain";
        var itemKeepOpen = input.CanPaste ? "Hint_PasteItemKeepOpen" : "Hint_CopyItemKeepOpen";
        var bits = input.Bits;
        var chips = new List<Chip>();

        switch (bits)
        {
            case ActionGrammar.Bits.None:
                chips.Add(input.CanPaste ? new Chip("Enter", "Verb_Paste") : new Chip("Enter", "Hint_CopyNoTarget", IsWarning: true));
                chips.Add(new Chip("Shift+Enter", "Hint_Plain"));
                chips.Add(new Chip("Space", "Hint_Preview"));
                chips.Add(new Chip("Ctrl+P", "Hint_Pin"));
                chips.Add(new Chip("Del", "Hint_Delete"));
                break;
            case ActionGrammar.Bits.CopyOnly:
                chips.Add(new Chip($"Ctrl+{NumberRow}", itemVerb));
                chips.Add(new Chip("Ctrl+Enter", "Verb_Copy"));
                chips.Add(new Chip("Ctrl+P", "Hint_Pin"));
                chips.Add(new Chip("Ctrl+Y", "Hint_Preview"));
                if (input.SelectedKind is ClipKind.Link or ClipKind.File or ClipKind.Image)
                {
                    chips.Add(new Chip("Ctrl+O", "Hint_Open"));
                }
                if (input.SelectedKind == ClipKind.File)
                {
                    chips.Add(new Chip("Ctrl+R", "Hint_Reveal"));
                }
                chips.Add(new Chip("Ctrl+Backspace", "Hint_Delete"));
                chips.Add(new Chip("Ctrl+Shift+Backspace", "Hint_Clear"));
                break;
            case ActionGrammar.Bits.Plain:
                chips.Add(new Chip("Shift+Enter", input.CanPaste ? "Verb_PastePlain" : "Verb_CopyPlain"));
                chips.Add(new Chip("Shift+click", "Hint_Same"));
                chips.Add(new Chip($"Ctrl+Shift+{NumberRow}", itemPlain));
                break;
            case ActionGrammar.Bits.KeepOpen:
                chips.Add(new Chip("Alt+Enter", input.CanPaste ? "Verb_PasteKeepOpen" : "Verb_CopyKeepOpen"));
                chips.Add(new Chip("Alt+click", "Hint_Same"));
                chips.Add(new Chip($"Ctrl+Alt+{NumberRow}", itemKeepOpen));
                break;
            case ActionGrammar.Bits.Plain | ActionGrammar.Bits.CopyOnly:
                chips.Add(new Chip("Ctrl+Shift+Enter", "Verb_CopyPlain"));
                chips.Add(new Chip($"Ctrl+Shift+{NumberRow}", itemPlain));
                break;
            case ActionGrammar.Bits.KeepOpen | ActionGrammar.Bits.CopyOnly:
                chips.Add(new Chip("Ctrl+Alt+Enter", "Verb_CopyKeepOpen"));
                chips.Add(new Chip($"Ctrl+Alt+{NumberRow}", itemKeepOpen));
                break;
            default:
            {
                // Shift+Alt with or without Ctrl: show the stacked result.
                var action = ActionGrammar.Resolve(ActionGrammar.Base.Return, bits, caps);
                chips.Add(new Chip($"{ActionGrammar.ModifierPrefix(bits)}Enter", ActionGrammar.VerbKey(action)));
                var numberAction = ActionGrammar.Resolve(new ActionGrammar.Base.Number(1), bits, caps);
                var numberBits = bits | ActionGrammar.Bits.CopyOnly;
                chips.Add(new Chip($"{ActionGrammar.ModifierPrefix(numberBits)}{NumberRow}", ActionGrammar.VerbKey(numberAction) + "_Item"));
                break;
            }
        }
        return chips;
    }
}
