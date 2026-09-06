using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Nori.Windows.Panel;
using Nori.Windows.Resources;

namespace Nori.Windows;

/// <summary>
/// The two-step first run: pick the shortcut, then decide whether Nori starts with Windows.
/// Finishing seeds a first clip so the very first Enter does something.
/// </summary>
internal sealed class WelcomeWindow : Window
{
    private readonly App _app;
    private readonly Theme _theme;
    private readonly StackPanel _body;
    private readonly StackPanel _dots;
    private readonly Border _back;
    private readonly Border _next;
    private int _step;

    public WelcomeWindow(App app, Theme theme)
    {
        _app = app;
        _theme = theme;
        Title = Strings.Get("App_Name");
        Width = 520;
        Height = 440;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = theme.WindowBackground;
        Foreground = theme.Primary;
        FontFamily = Theme.UiFont;
        FontSize = 13;
        Topmost = app.Options.IsScreenshotMode;

        _body = new StackPanel { Margin = new Thickness(40, 32, 40, 0), VerticalAlignment = VerticalAlignment.Top };
        _dots = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        _back = Ui.FlatButton(theme, Strings.Get("Welcome_Back"), () => Show(_step - 1));
        _next = Ui.FlatButton(theme, Strings.Get("Welcome_Next"), () => Advance(), accent: true);

        var footer = new Grid { Margin = new Thickness(24, 0, 24, 20), VerticalAlignment = VerticalAlignment.Bottom };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(_back, 0);
        Grid.SetColumn(_dots, 1);
        Grid.SetColumn(_next, 2);
        _dots.HorizontalAlignment = HorizontalAlignment.Center;
        footer.Children.Add(_back);
        footer.Children.Add(_dots);
        footer.Children.Add(_next);

        var root = new Grid();
        root.Children.Add(_body);
        root.Children.Add(footer);
        Content = root;

        Show(0);
    }

    private void Advance()
    {
        if (_step == 0)
        {
            Show(1);
            return;
        }
        _app.WelcomeFinished();
        Close();
    }

    private void Show(int step)
    {
        _step = Math.Clamp(step, 0, 1);
        _body.Children.Clear();
        _body.Children.Add(Heading(_step == 0 ? "Welcome_Title1" : "Welcome_Title2"));
        _body.Children.Add(Body(_step == 0 ? "Welcome_Body1" : "Welcome_Body2"));
        _body.Children.Add(_step == 0 ? HotkeyStep() : LoginStep());

        _back.Visibility = _step == 0 ? Visibility.Hidden : Visibility.Visible;
        ((TextBlock)_next.Child).Text = Strings.Get(_step == 0 ? "Welcome_Next" : "Welcome_Done");

        _dots.Children.Clear();
        for (var i = 0; i < 2; i++)
        {
            _dots.Children.Add(new Border
            {
                Width = 7,
                Height = 7,
                CornerRadius = new CornerRadius(3.5),
                Margin = new Thickness(4, 0, 4, 0),
                Background = i == _step ? _theme.AccentBrush : _theme.Separator,
            });
        }
    }

    private TextBlock Heading(string key)
    {
        var block = Ui.Text(Strings.Get(key), 22, _theme.Primary, FontWeights.SemiBold);
        block.HorizontalAlignment = HorizontalAlignment.Center;
        block.TextAlignment = TextAlignment.Center;
        block.TextWrapping = TextWrapping.Wrap;
        return block;
    }

    private TextBlock Body(string key)
    {
        var block = Ui.Text(Strings.Get(key), 13, _theme.Secondary);
        block.HorizontalAlignment = HorizontalAlignment.Center;
        block.TextAlignment = TextAlignment.Center;
        block.TextWrapping = TextWrapping.Wrap;
        block.Margin = new Thickness(0, 10, 0, 0);
        return block;
    }

    /// <summary>Step 1: the three shortcut presets, the current one highlighted.</summary>
    private UIElement HotkeyStep()
    {
        var stack = new StackPanel { Margin = new Thickness(0, 24, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        var caption = Ui.Text(Strings.Get("General_HotkeyCaption"), 12, _theme.Secondary);
        caption.TextWrapping = TextWrapping.Wrap;
        caption.TextAlignment = TextAlignment.Center;
        caption.Margin = new Thickness(0, 16, 0, 0);
        caption.MaxWidth = 400;

        foreach (var preset in Enum.GetValues<HotkeyPreset>())
        {
            var selected = _app.Settings.Hotkey == preset;
            var button = Ui.FlatButton(_theme, preset.DisplayText(), () =>
            {
                if (!_app.ApplyHotkey(preset))
                {
                    caption.Text = Strings.Format("Hotkey_Failed", preset.DisplayText());
                    caption.Foreground = _theme.Warning;
                    return;
                }
                caption.Text = Strings.Get("General_HotkeyCaption");
                caption.Foreground = _theme.Secondary;
                Show(_step);
            }, accent: selected);
            button.Margin = new Thickness(4, 0, 4, 0);
            row.Children.Add(button);
        }

        stack.Children.Add(row);
        stack.Children.Add(caption);
        return stack;
    }

    /// <summary>Step 2: start with Windows.</summary>
    private UIElement LoginStep()
    {
        var stack = new StackPanel { Margin = new Thickness(0, 28, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
        var toggle = new CheckBox
        {
            Content = Ui.Text(Strings.Get("General_StartWithWindows"), 13, _theme.Primary),
            IsChecked = NoriSettings.StartsWithWindows,
            Foreground = _theme.Primary,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        toggle.Checked += (_, _) => NoriSettings.SetStartsWithWindows(true);
        toggle.Unchecked += (_, _) => NoriSettings.SetStartsWithWindows(false);
        stack.Children.Add(toggle);
        return stack;
    }
}
