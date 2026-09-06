namespace Nori.Windows;

/// <summary>
/// Command-line switches. Normal launches carry none; CI drives the app with
/// <c>--in-memory --seed-demo --state &lt;name&gt; --screenshot &lt;path&gt;</c>.
/// </summary>
internal sealed record LaunchOptions
{
    public bool InMemory { get; init; }
    public bool SeedDemo { get; init; }
    public string State { get; init; } = "default";
    public string? ScreenshotPath { get; init; }
    /// <summary>Open the panel right after launch (handy for manual testing).</summary>
    public bool OpenAtLaunch { get; init; }

    public bool IsScreenshotMode => ScreenshotPath is not null;

    /// <summary>Screenshots and demo data use a frozen clock so relative times never drift between runs.</summary>
    public bool UsesFixedClock => IsScreenshotMode || SeedDemo;

    public static readonly DateTimeOffset FixedNow = new(2026, 9, 5, 10, 0, 0, TimeZoneInfo.Local.GetUtcOffset(new DateTime(2026, 9, 5, 10, 0, 0)));

    public static readonly IReadOnlyList<string> KnownStates =
    [
        "default", "search:swift", "filter:code", "cmd", "shift", "expanded:4", "ghost", "empty", "dark", "settings", "onboarding",
    ];

    public static LaunchOptions Parse(IReadOnlyList<string> args)
    {
        var options = new LaunchOptions();
        for (var i = 0; i < args.Count; i++)
        {
            var arg = args[i];
            string? Next() => i + 1 < args.Count ? args[++i] : null;
            switch (arg)
            {
                case "--in-memory":
                    options = options with { InMemory = true };
                    break;
                case "--seed-demo":
                    options = options with { SeedDemo = true };
                    break;
                case "--open":
                    options = options with { OpenAtLaunch = true };
                    break;
                case "--state":
                    options = options with { State = Next() ?? "default" };
                    break;
                case "--screenshot":
                    options = options with { ScreenshotPath = Next() };
                    break;
                default:
                    if (arg.StartsWith("--state=", StringComparison.Ordinal)) options = options with { State = arg["--state=".Length..] };
                    else if (arg.StartsWith("--screenshot=", StringComparison.Ordinal)) options = options with { ScreenshotPath = arg["--screenshot=".Length..] };
                    break;
            }
        }
        // A screenshot never touches the real history, and the "empty" state has nothing to seed.
        if (options.IsScreenshotMode)
        {
            options = options with { InMemory = true, SeedDemo = options.State != "empty" };
        }
        return options;
    }
}
