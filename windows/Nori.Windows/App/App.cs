using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Nori.Core;
using Nori.Windows.Clipboard;
using Nori.Windows.Panel;
using Nori.Windows.Resources;
using Nori.Windows.Storage;

namespace Nori.Windows;

/// <summary>
/// The composition root: owns the store, the clipboard listener, the hotkey, the tray icon and the panel,
/// and is the single object every other piece talks to.
/// </summary>
internal sealed class App : Application
{
    private readonly SqliteClipRepository? _repository;
    private MessageWindow? _messages;
    private TrayIcon? _tray;
    private SettingsWindow? _settingsWindow;
    private WelcomeWindow? _welcomeWindow;
    private DispatcherTimer? _housekeeping;
    private bool _storeWasReset;

    public App(LaunchOptions options)
    {
        Options = options;
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        Clock = options.UsesFixedClock ? new FixedClock(LaunchOptions.FixedNow) : new SystemClock();
        Settings = options.InMemory ? NoriSettings.Ephemeral() : NoriSettings.Load();

        IClipRepository repository;
        if (options.InMemory)
        {
            repository = new InMemoryClipRepository();
        }
        else
        {
            _repository = SqliteClipRepository.Open(Path.Combine(Log.DataDirectory, "history.db"), out _storeWasReset);
            repository = _repository;
        }

        History = new HistoryStore(repository) { MaxItems = Settings.MaxItems, ExpireAfterDays = Settings.ExpireAfterDays };
        Vault = new SensitiveVault();
        Apps = new SourceApps();
        Capture = new CaptureService(Settings, History, Vault, Apps, Clock);
        Panel = new PanelController(this);
    }

    public LaunchOptions Options { get; }
    public IClock Clock { get; }
    public NoriSettings Settings { get; }
    public HistoryStore History { get; }
    public SensitiveVault Vault { get; }
    public SourceApps Apps { get; }
    public CaptureService Capture { get; }
    public PanelController Panel { get; }

    public static string Version =>
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0]
        ?? "0.1.0";

    /// <summary>The app icon at a given edge length, loaded from the embedded .ico.</summary>
    public static ImageSource? AppIconImage(int size)
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Nori.Windows.Assets.nori.ico");
            if (stream is null) return null;
            var decoder = new IconBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            // Icons carry several sizes; take the smallest frame that still covers the requested edge.
            var best = decoder.Frames.Where(f => f.PixelWidth >= size).OrderBy(f => f.PixelWidth).FirstOrDefault()
                ?? decoder.Frames.OrderByDescending(f => f.PixelWidth).FirstOrDefault();
            return best;
        }
        catch (Exception e)
        {
            Log.Error("app icon could not be loaded", e);
            return null;
        }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        History.Load();
        History.ExpireOldItems(Clock.Now);

        if (Options.SeedDemo)
        {
            DemoSeeder.Seed(History, Vault, Clock.Now);
        }

        if (Options.IsScreenshotMode)
        {
            RunScreenshot();
            return;
        }

        _messages = new MessageWindow();
        _messages.ClipboardUpdated += Capture.OnClipboardUpdated;
        _messages.HotkeyPressed += OnHotkey;
        _messages.StartClipboardListener();
        if (!_messages.RegisterHotkey(Settings.Hotkey))
        {
            Log.Warn($"hotkey {Settings.Hotkey.DisplayText()} is taken by another app");
        }

        Capture.Changed += () => Panel.RowsChanged();
        Capture.PauseChanged += () => { _tray?.Refresh(); Panel.PauseStateChanged(); };

        _tray = new TrayIcon(this);

        // Expiry, the sensitive-vault sweep and the pause countdown all tick here.
        _housekeeping = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromSeconds(30) };
        _housekeeping.Tick += (_, _) =>
        {
            Capture.SweepVault();
            if (History.ExpireOldItems(Clock.Now) > 0) Panel.RowsChanged();
            _tray?.Refresh();
        };
        _housekeeping.Start();

        if (_storeWasReset)
        {
            Log.Warn("history.db could not be opened and was reset");
        }

        if (!Settings.HasCompletedOnboarding && !Options.InMemory)
        {
            ShowWelcome();
        }
        else if (Options.OpenAtLaunch)
        {
            Panel.Open();
        }

        Log.Info($"Nori {Version} started with {History.Rows.Count} clips");
    }

    /// <summary>Renders one <c>--state</c> to a PNG and exits; this is how CI verifies the UI.</summary>
    private void RunScreenshot()
    {
        var path = Options.ScreenshotPath!;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)) ?? ".");
        var state = Options.State;

        switch (state)
        {
            case "settings":
                var settings = new SettingsWindow(this, CurrentTheme());
                settings.Show();
                Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () =>
                {
                    settings.UpdateLayout();
                    PanelWindow.RenderVisual((FrameworkElement)settings.Content, settings.Width, settings.Height, 1, path);
                    Shutdown(0);
                });
                return;

            case "onboarding":
                var welcome = new WelcomeWindow(this, CurrentTheme());
                welcome.Show();
                Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () =>
                {
                    welcome.UpdateLayout();
                    PanelWindow.RenderVisual((FrameworkElement)welcome.Content, welcome.Width, welcome.Height, 1, path);
                    Shutdown(0);
                });
                return;

            case "empty":
                History.Clear(includingPinned: true);
                Vault.RemoveAll();
                break;

            case "dark":
                Panel.ForceDark();
                break;
        }

        Panel.OpenForScreenshot(state);
        Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () =>
        {
            Panel.RenderScreenshot(path);
            Shutdown(0);
        });
    }

    private Theme CurrentTheme() => new(Theme.SystemPrefersDark(), Theme.SystemAccent());

    /// <summary>The chord opens the panel, and closes it when it is already up.</summary>
    private void OnHotkey() => Panel.Toggle();

    // MARK: - Actions used by the tray, the settings window and the panel

    public void OpenSettings(int tab)
    {
        Panel.Close();
        if (_settingsWindow is null || !_settingsWindow.IsLoaded)
        {
            _settingsWindow = new SettingsWindow(this, CurrentTheme());
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }
        _settingsWindow.SelectTab(tab);
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    public void ShowWelcome()
    {
        Panel.Close();
        if (_welcomeWindow is null || !_welcomeWindow.IsLoaded)
        {
            _welcomeWindow = new WelcomeWindow(this, CurrentTheme());
            _welcomeWindow.Closed += (_, _) => _welcomeWindow = null;
        }
        _welcomeWindow.Show();
        _welcomeWindow.Activate();
    }

    /// <summary>Called when the welcome flow finishes: remember it and seed a first clip.</summary>
    public void WelcomeFinished()
    {
        Settings.HasCompletedOnboarding = true;
        Settings.Save();
        if (History.Rows.Count == 0)
        {
            DemoSeeder.SeedWelcome(History, Clock.Now);
        }
        Panel.RowsChanged();
        Panel.Open(PanelPosition.Center);
    }

    public void ConfirmClearHistory(Window? owner = null)
    {
        var unpinned = History.Rows.Count(r => !r.IsPinned);
        var pinned = History.Rows.Count - unpinned;
        var dialog = new ClearHistoryDialog(CurrentTheme(), unpinned, pinned) { Owner = owner };
        if (dialog.ShowDialog() == true)
        {
            ClearHistory(dialog.IncludePinned);
        }
    }

    public int ClearHistory(bool includingPinned)
    {
        var cleared = History.Clear(includingPinned);
        Vault.RemoveAll();
        Panel.RowsChanged();
        _tray?.Refresh();
        return cleared;
    }

    public void PauseCapture(TimeSpan? duration)
    {
        Capture.Pause(duration);
        _tray?.Refresh();
    }

    public void ResumeCapture()
    {
        Capture.Resume();
        _tray?.Refresh();
    }

    public void TogglePause()
    {
        if (Capture.PauseUntil is not null) ResumeCapture();
        else PauseCapture(null);
    }

    /// <summary>Registers a new chord; false (and the old one restored) when another app owns it.</summary>
    public bool ApplyHotkey(HotkeyPreset preset)
    {
        var previous = Settings.Hotkey;
        Settings.Hotkey = preset;
        if (_messages is null) return true;
        if (_messages.RegisterHotkey(preset))
        {
            Settings.Save();
            _tray?.Refresh();
            return true;
        }
        Settings.Hotkey = previous;
        _messages.RegisterHotkey(previous);
        return false;
    }

    /// <summary>Any settings change: persist, and re-apply what the running services cache.</summary>
    public void SettingsChanged()
    {
        Settings.Save();
        History.MaxItems = Settings.MaxItems;
        History.ExpireAfterDays = Settings.ExpireAfterDays;
        History.ExpireOldItems(Clock.Now);
        Panel.RowsChanged();
        _tray?.Refresh();
    }

    public void Quit()
    {
        if (Settings.ClearOnQuit) History.Clear(includingPinned: false);
        Vault.RemoveAll();
        Shutdown(0);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _housekeeping?.Stop();
        _tray?.Dispose();
        _messages?.Dispose();
        _repository?.Dispose();
        base.OnExit(e);
    }
}

/// <summary>A clock frozen at one instant, so seeded demo data and screenshots never drift.</summary>
internal sealed class FixedClock(DateTimeOffset now) : IClock
{
    public DateTimeOffset Now { get; } = now;
}
