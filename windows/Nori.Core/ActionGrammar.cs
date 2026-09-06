namespace Nori.Core;

/// <summary>
/// The single source of truth for what a key, click or number does.
/// Enter pastes. Modifiers are orthogonal bits: Shift = plain text, Alt = keep the panel open,
/// Ctrl = copy only. No preference can change this; the hint bar renders from the same function.
/// </summary>
public static class ActionGrammar
{
    public abstract record Base
    {
        public sealed record ReturnKey : Base;
        public sealed record Click : Base;
        public sealed record Number(int Value) : Base;

        public static readonly Base Return = new ReturnKey();
        public static readonly Base Mouse = new Click();
    }

    [Flags]
    public enum Bits
    {
        None = 0,
        Plain = 1 << 0,     // Shift
        KeepOpen = 1 << 1,  // Alt
        CopyOnly = 1 << 2,  // Ctrl
    }

    /// <summary>Every combination of the three bits, for truth-table tests.</summary>
    public static readonly IReadOnlyList<Bits> AllBits = Enumerable.Range(0, 8).Select(i => (Bits)i).ToList();

    /// <summary>
    /// On Windows a synthetic Ctrl+V needs no special permission, so pasting is normally possible.
    /// The flag stays so a degraded environment (no foreground window to paste into) can turn Enter into Copy.
    /// </summary>
    public readonly record struct Capabilities(bool CanPaste);

    public readonly record struct Action(bool IsPaste, bool Plain, bool KeepOpen)
    {
        public static Action Paste(bool plain, bool keepOpen) => new(true, plain, keepOpen);
        public static Action Copy(bool plain, bool keepOpen) => new(false, plain, keepOpen);
        public bool IsCopy => !IsPaste;
    }

    public static Action Resolve(Base @base, Bits bits, Capabilities caps)
    {
        var plain = bits.HasFlag(Bits.Plain);
        var keepOpen = bits.HasFlag(Bits.KeepOpen);
        // Ctrl is the trigger of the number row, so it cannot also mean "copy only" there.
        var copyOnly = @base is not Base.Number && bits.HasFlag(Bits.CopyOnly);
        if (copyOnly || !caps.CanPaste)
        {
            return Action.Copy(plain, keepOpen);
        }
        return Action.Paste(plain, keepOpen);
    }

    /// <summary>Resource key of the verb for hint bars and menus (English text lives in the app's resources).</summary>
    public static string VerbKey(Action action) => (action.IsPaste, action.Plain, action.KeepOpen) switch
    {
        (true, false, false) => "Verb_Paste",
        (true, true, false) => "Verb_PastePlain",
        (true, false, true) => "Verb_PasteKeepOpen",
        (true, true, true) => "Verb_PastePlainKeepOpen",
        (false, false, false) => "Verb_Copy",
        (false, true, false) => "Verb_CopyPlain",
        (false, false, true) => "Verb_CopyKeepOpen",
        (false, true, true) => "Verb_CopyPlainKeepOpen",
    };

    /// <summary>Default English verb, used by tests and as the fallback when a resource is missing.</summary>
    public static string EnglishVerb(Action action) => (action.IsPaste, action.Plain, action.KeepOpen) switch
    {
        (true, false, false) => "Paste",
        (true, true, false) => "Paste as plain text",
        (true, false, true) => "Paste and keep Nori open",
        (true, true, true) => "Paste plain, keep open",
        (false, false, false) => "Copy",
        (false, true, false) => "Copy as plain text",
        (false, false, true) => "Copy, keep open",
        (false, true, true) => "Copy plain, keep open",
    };

    /// <summary>Modifier prefix in the Windows order (Ctrl, Alt, Shift) for keycaps, e.g. "Ctrl+Shift+".</summary>
    public static string ModifierPrefix(Bits bits)
    {
        var result = string.Empty;
        if (bits.HasFlag(Bits.CopyOnly)) result += "Ctrl+";
        if (bits.HasFlag(Bits.KeepOpen)) result += "Alt+";
        if (bits.HasFlag(Bits.Plain)) result += "Shift+";
        return result;
    }

    /// <summary>Translate a modifier state into grammar bits.</summary>
    public static Bits FromModifiers(bool shift, bool alt, bool control)
    {
        var bits = Bits.None;
        if (shift) bits |= Bits.Plain;
        if (alt) bits |= Bits.KeepOpen;
        if (control) bits |= Bits.CopyOnly;
        return bits;
    }
}
