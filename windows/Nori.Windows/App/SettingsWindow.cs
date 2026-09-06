using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using Nori.Core;
using Nori.Windows.Panel;
using Nori.Windows.Resources;

namespace Nori.Windows;

/// <summary>Settings: five tabs (General, Capture, Privacy, Look, About), plain WPF controls, saved on change.</summary>
internal sealed class SettingsWindow : Window
{
    private readonly App _app;
    private readonly Theme _theme;
    private readonly TabControl _tabs;

    public SettingsWindow(App app, Theme theme)
    {
        _app = app;
        _theme = theme;
        Title = Strings.Get("Settings_Title");
        Width = 560;
        Height = 520;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = theme.WindowBackground;
        Foreground = theme.Primary;
        FontFamily = Theme.UiFont;
        FontSize = 13;
        ShowInTaskbar = true;
        Topmost = app.Options.IsScreenshotMode;

        _tabs = new TabControl { Margin = new Thickness(12), Background = Theme.Transparent, BorderThickness = new Thickness(0) };
        _tabs.Items.Add(Tab("Tab_General", General()));
        _tabs.Items.Add(Tab("Tab_Capture", Capture()));
        _tabs.Items.Add(Tab("Tab_Privacy", Privacy()));
        _tabs.Items.Add(Tab("Tab_Look", Look()));
        _tabs.Items.Add(Tab("Tab_About", About()));
        Content = _tabs;
    }

    public void SelectTab(int index) => _tabs.SelectedIndex = Math.Clamp(index, 0, _tabs.Items.Count - 1);

    private TabItem Tab(string key, UIElement content) => new()
    {
        Header = Strings.Get(key),
        Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(16) },
        Foreground = _theme.Primary,
    };

    private TextBlock Label(string key, bool caption = false)
    {
        var block = Ui.Text(Strings.Get(key), caption ? 11 : 13, caption ? _theme.Secondary : _theme.Primary);
        block.TextWrapping = TextWrapping.Wrap;
        block.TextTrimming = TextTrimming.None;
        block.Margin = new Thickness(0, caption ? 2 : 12, 0, 4);
        return block;
    }

    private CheckBox Check(string key, bool value, Action<bool> changed)
    {
        var box = new CheckBox { Content = Strings.Get(key), IsChecked = value, Margin = new Thickness(0, 6, 0, 0), Foreground = _theme.Primary };
        box.Checked += (_, _) => changed(true);
        box.Unchecked += (_, _) => changed(false);
        return box;
    }

    private ComboBox Combo(IReadOnlyList<string> options, int selected, Action<int> changed)
    {
        var combo = new ComboBox { Width = 220, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 4, 0, 0) };
        foreach (var option in options) combo.Items.Add(option);
        combo.SelectedIndex = Math.Clamp(selected, 0, options.Count - 1);
        combo.SelectionChanged += (_, _) => { if (combo.SelectedIndex >= 0) changed(combo.SelectedIndex); };
        return combo;
    }

    private void Save() => _app.SettingsChanged();

    // MARK: - General

    private UIElement General()
    {
        var settings = _app.Settings;
        var stack = new StackPanel();
        stack.Children.Add(Label("General_Hotkey"));
        var presets = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var preset in Enum.GetValues<HotkeyPreset>())
        {
            var radio = new RadioButton
            {
                Content = preset.DisplayText(),
                GroupName = "hotkey",
                IsChecked = settings.Hotkey == preset,
                Margin = new Thickness(0, 0, 18, 0),
                Foreground = _theme.Primary,
            };
            var captured = preset;
            radio.Checked += (_, _) =>
            {
                if (settings.Hotkey == captured) return;
                settings.Hotkey = captured;
                Save();
                if (!_app.ApplyHotkey(captured))
                {
                    System.Windows.MessageBox.Show(this, Strings.Format("Hotkey_Failed", captured.DisplayText()), Strings.Get("App_Name"), MessageBoxButton.OK, MessageBoxImage.Warning);
                }
            };
            presets.Children.Add(radio);
        }
        stack.Children.Add(presets);
        stack.Children.Add(Label("General_HotkeyCaption", caption: true));

        stack.Children.Add(Check("General_StartWithWindows", NoriSettings.StartsWithWindows, NoriSettings.SetStartsWithWindows));

        stack.Children.Add(Label("General_Position"));
        stack.Children.Add(Combo([Strings.Get("Position_Cursor"), Strings.Get("Position_Center"), Strings.Get("Position_Tray")], (int)settings.PanelPosition, index =>
        {
            settings.PanelPosition = (PanelPosition)index;
            Save();
        }));

        var welcome = Ui.FlatButton(_theme, Strings.Get("General_ShowWelcome"), () => { _app.ShowWelcome(); });
        welcome.HorizontalAlignment = HorizontalAlignment.Left;
        welcome.Margin = new Thickness(0, 20, 0, 0);
        stack.Children.Add(welcome);
        return stack;
    }

    // MARK: - Capture

    private UIElement Capture()
    {
        var settings = _app.Settings;
        var stack = new StackPanel();
        stack.Children.Add(Label("Capture_Remember"));
        stack.Children.Add(Check("Capture_Text", settings.CaptureText, v => { settings.CaptureText = v; Save(); }));
        stack.Children.Add(Check("Capture_Images", settings.CaptureImages, v => { settings.CaptureImages = v; Save(); }));
        stack.Children.Add(Check("Capture_Files", settings.CaptureFiles, v => { settings.CaptureFiles = v; Save(); }));

        stack.Children.Add(Label("Capture_KeepUpTo"));
        var counts = Enumerable.Range(1, 20).Select(i => i * 100).ToList();
        var keepRow = new StackPanel { Orientation = Orientation.Horizontal };
        keepRow.Children.Add(Combo(counts.Select(c => c.ToString(Strings.Culture)).ToList(), counts.IndexOf(settings.MaxItems) is var idx && idx >= 0 ? idx : 4, index =>
        {
            settings.MaxItems = counts[index];
            Save();
        }));
        var clips = Ui.Text(Strings.Get("Capture_Clips"), 12, _theme.Secondary);
        clips.Margin = new Thickness(8, 4, 0, 0);
        keepRow.Children.Add(clips);
        stack.Children.Add(keepRow);

        stack.Children.Add(Label("Capture_Forget"));
        var days = new[] { 0, 1, 7, 30 };
        stack.Children.Add(Combo([Strings.Get("Forget_Never"), Strings.Get("Forget_Day"), Strings.Get("Forget_Week"), Strings.Get("Forget_Month")],
            Math.Max(0, Array.IndexOf(days, settings.ExpireAfterDays)), index =>
            {
                settings.ExpireAfterDays = days[index];
                Save();
            }));

        stack.Children.Add(Label("Capture_LargestImage"));
        var sizes = new[] { 5, 10, 25, 50 };
        stack.Children.Add(Combo(sizes.Select(s => $"{s} MB").ToList(), Math.Max(0, Array.IndexOf(sizes, settings.MaxImageMegabytes)), index =>
        {
            settings.MaxImageMegabytes = sizes[index];
            Save();
        }));

        stack.Children.Add(Label("Capture_IgnoreRegex"));
        var regexes = new TextBox
        {
            Text = string.Join(Environment.NewLine, settings.IgnoreRegexes),
            AcceptsReturn = true,
            MinHeight = 70,
            FontFamily = Theme.MonoFont,
            FontSize = 12,
            TextWrapping = TextWrapping.NoWrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        regexes.LostFocus += (_, _) =>
        {
            settings.IgnoreRegexes = regexes.Text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
            Save();
        };
        stack.Children.Add(regexes);
        return stack;
    }

    // MARK: - Privacy

    private UIElement Privacy()
    {
        var settings = _app.Settings;
        var stack = new StackPanel();
        stack.Children.Add(Label("Privacy_IgnoredApps"));
        var list = new ListBox { Height = 120, FontSize = 12 };
        foreach (var app in settings.IgnoredApps) list.Items.Add(app);
        stack.Children.Add(list);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        var add = Ui.FlatButton(_theme, Strings.Get("Privacy_Add"), () =>
        {
            var dialog = new OpenFileDialog { Filter = Strings.Get("FileDialog_Apps"), Title = Strings.Get("FileDialog_Title") };
            if (dialog.ShowDialog(this) != true) return;
            var exe = System.IO.Path.GetFileName(dialog.FileName);
            if (settings.IgnoredApps.Contains(exe, StringComparer.OrdinalIgnoreCase)) return;
            settings.IgnoredApps.Add(exe);
            list.Items.Add(exe);
            Save();
        });
        add.Margin = new Thickness(0, 0, 8, 0);
        buttons.Children.Add(add);
        buttons.Children.Add(Ui.FlatButton(_theme, Strings.Get("Privacy_Remove"), () =>
        {
            if (list.SelectedItem is not string exe) return;
            settings.IgnoredApps.RemoveAll(a => string.Equals(a, exe, StringComparison.OrdinalIgnoreCase));
            list.Items.Remove(exe);
            Save();
        }));
        stack.Children.Add(buttons);

        stack.Children.Add(Check("Privacy_MaskSecrets", settings.MaskSensitive, v => { settings.MaskSensitive = v; Save(); }));
        stack.Children.Add(Label("Privacy_MaskSecretsCaption", caption: true));
        stack.Children.Add(Check("Privacy_GhostRows", settings.ShowGhostRows, v => { settings.ShowGhostRows = v; Save(); }));
        stack.Children.Add(Check("Privacy_ClearOnQuit", settings.ClearOnQuit, v => { settings.ClearOnQuit = v; Save(); }));

        stack.Children.Add(Label("Privacy_StorageNote", caption: true));
        stack.Children.Add(Label("Privacy_StorageUsed"));
        var storage = Ui.Text(StorageText(), 12, _theme.Secondary);
        stack.Children.Add(storage);
        var clear = Ui.FlatButton(_theme, Strings.Get("Privacy_ClearHistory"), () =>
        {
            _app.ConfirmClearHistory(this);
            storage.Text = StorageText();
        });
        clear.HorizontalAlignment = HorizontalAlignment.Left;
        clear.Margin = new Thickness(0, 12, 0, 0);
        stack.Children.Add(clear);
        return stack;
    }

    private string StorageText()
    {
        long bytes;
        try { bytes = _app.History.StorageBytes(); }
        catch (Exception) { bytes = 0; }
        return Strings.Format("Privacy_StorageValue", ByteSize.Format(bytes), _app.History.Count, _app.History.PinnedCount);
    }

    // MARK: - Look

    private UIElement Look()
    {
        var settings = _app.Settings;
        var stack = new StackPanel();
        stack.Children.Add(Check("Look_AppIcons", settings.ShowAppIcons, v => { settings.ShowAppIcons = v; Save(); }));
        stack.Children.Add(Check("Look_Keycaps", settings.ShowKeycaps, v => { settings.ShowKeycaps = v; Save(); }));
        stack.Children.Add(Check("Look_HintBar", settings.ShowHintBar, v => { settings.ShowHintBar = v; Save(); }));
        return stack;
    }

    // MARK: - About

    private UIElement About()
    {
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 24, 0, 0) };
        var icon = App.AppIconImage(96);
        if (icon is not null)
        {
            var image = new Image { Source = icon, Width = 96, Height = 96, HorizontalAlignment = HorizontalAlignment.Center };
            stack.Children.Add(image);
        }
        void Add(string text, double size, Brush brush, FontWeight? weight = null, double top = 6)
        {
            var block = Ui.Text(text, size, brush, weight);
            block.HorizontalAlignment = HorizontalAlignment.Center;
            block.TextWrapping = TextWrapping.Wrap;
            block.TextAlignment = TextAlignment.Center;
            block.Margin = new Thickness(0, top, 0, 0);
            stack.Children.Add(block);
        }
        Add(Strings.Get("App_Name"), 20, _theme.Primary, FontWeights.SemiBold, 12);
        Add(Strings.Format("About_Version", App.Version), 12, _theme.Secondary, top: 2);
        Add(Strings.Get("About_Tagline"), 13, _theme.Primary, top: 14);
        var link = Ui.Text("github.com/hocky0301/Nori", 12, _theme.AccentBrush);
        link.HorizontalAlignment = HorizontalAlignment.Center;
        link.Margin = new Thickness(0, 10, 0, 0);
        link.Cursor = System.Windows.Input.Cursors.Hand;
        link.MouseLeftButtonUp += (_, _) =>
        {
            try { Process.Start(new ProcessStartInfo("https://github.com/hocky0301/Nori") { UseShellExecute = true }); }
            catch (Exception e) { Log.Warn($"link could not be opened: {e.Message}"); }
        };
        stack.Children.Add(link);
        Add(Strings.Get("About_Inspired"), 12, _theme.Secondary, top: 14);
        Add(Strings.Get("About_License"), 12, _theme.Secondary, top: 2);
        Add(Strings.Get("About_Privacy"), 12, _theme.Secondary, top: 14);
        return stack;
    }
}
