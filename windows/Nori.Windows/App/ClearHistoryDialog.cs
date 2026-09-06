using System.Windows;
using System.Windows.Controls;
using Nori.Windows.Panel;
using Nori.Windows.Resources;

namespace Nori.Windows;

/// <summary>"Clear history?" — used by the tray menu and the Privacy tab. The panel has its own inline sheet.</summary>
internal sealed class ClearHistoryDialog : Window
{
    private readonly CheckBox _includePinned;

    public bool IncludePinned => _includePinned.IsChecked == true;

    public ClearHistoryDialog(Theme theme, int unpinned, int pinned)
    {
        Title = Strings.Get("Clear_Title");
        Width = 380;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = theme.WindowBackground;
        Foreground = theme.Primary;
        FontFamily = Theme.UiFont;
        FontSize = 13;

        var body = Ui.Text(Strings.Format("Clear_Body", unpinned), 13, theme.Primary);
        body.TextWrapping = TextWrapping.Wrap;

        _includePinned = new CheckBox
        {
            Content = Ui.Text(Strings.Get("Clear_IncludePinned"), 12, theme.Secondary),
            Margin = new Thickness(0, 14, 0, 0),
            Foreground = theme.Primary,
            IsEnabled = pinned > 0,
        };
        _includePinned.Checked += (_, _) => body.Text = Strings.Format("Clear_BodyPinned", unpinned + pinned);
        _includePinned.Unchecked += (_, _) => body.Text = Strings.Format("Clear_Body", unpinned);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 22, 0, 0),
        };
        var cancel = Ui.FlatButton(theme, Strings.Get("Dialog_Cancel"), () => { DialogResult = false; Close(); });
        var clear = Ui.FlatButton(theme, Strings.Get("Clear_Confirm"), () => { DialogResult = true; Close(); }, accent: true);
        clear.Margin = new Thickness(8, 0, 0, 0);
        buttons.Children.Add(cancel);
        buttons.Children.Add(clear);

        var stack = new StackPanel { Margin = new Thickness(22) };
        stack.Children.Add(body);
        stack.Children.Add(_includePinned);
        stack.Children.Add(buttons);
        Content = stack;

        // Esc cancels, Enter clears.
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Escape) { DialogResult = false; Close(); }
            else if (e.Key == System.Windows.Input.Key.Enter) { DialogResult = true; Close(); }
        };
    }
}
