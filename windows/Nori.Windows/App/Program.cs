using System.Globalization;
using System.Threading;

namespace Nori.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var options = LaunchOptions.Parse(args);
        Log.Initialize(echoToConsole: options.IsScreenshotMode);

        // CI images must not change with the runner's language.
        if (options.IsScreenshotMode)
        {
            Resources.Strings.Culture = CultureInfo.GetCultureInfo("en");
        }

        // One Nori per session — a second launch just wakes the first one. Screenshot runs are exempt
        // so CI can render several states in parallel.
        using var single = new Mutex(initiallyOwned: true, "Local\\NoriSingleInstance", out var isFirst);
        if (!isFirst && !options.IsScreenshotMode)
        {
            Log.Info("another Nori is already running; exiting");
            return 0;
        }

        try
        {
            var app = new App(options);
            return app.Run();
        }
        catch (Exception e)
        {
            Log.Error("Nori stopped with an unhandled error", e);
            return 1;
        }
    }
}
