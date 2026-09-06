using System.Windows.Forms;
using Nori.Core;
using Nori.Windows.Resources;

namespace Nori.Windows;

/// <summary>The notification-area icon and its menu (WinForms NotifyIcon; the only WinForms surface).</summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly App _app;
    private readonly NotifyIcon _icon;
    private readonly System.Drawing.Icon? _normal;
    private readonly System.Drawing.Icon? _paused;

    public TrayIcon(App app)
    {
        _app = app;
        _normal = LoadIcon();
        _paused = _normal is null ? null : Dim(_normal);
        _icon = new NotifyIcon
        {
            Icon = _normal,
            Visible = true,
            Text = Strings.Format("Tray_Tooltip", app.Settings.Hotkey.DisplayText()),
        };
        _icon.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left) _app.Panel.Toggle(PanelPosition.Tray);
        };
        _icon.ContextMenuStrip = new ContextMenuStrip();
        _icon.ContextMenuStrip.Opening += (_, _) => RebuildMenu();
        RebuildMenu();
    }

    public void Refresh()
    {
        var paused = _app.Capture.IsPaused;
        _icon.Icon = paused ? _paused ?? _normal : _normal;
        _icon.Text = paused ? Strings.Get("Tray_TooltipPaused") : Strings.Format("Tray_Tooltip", _app.Settings.Hotkey.DisplayText());
    }

    private void RebuildMenu()
    {
        var menu = _icon.ContextMenuStrip!;
        menu.Items.Clear();
        menu.Items.Add(new ToolStripMenuItem(Strings.Get("Tray_Open"), null, (_, _) => _app.Panel.Toggle(PanelPosition.Tray))
        {
            ShortcutKeyDisplayString = _app.Settings.Hotkey.DisplayText(),
        });
        menu.Items.Add(new ToolStripSeparator());
        if (_app.Capture.IsPaused)
        {
            var caption = _app.Capture.PauseRemaining is { } remaining
                ? $"{Strings.Get("Tray_Resume")}  ({Strings.Format("Tray_PausedCaption", $"{(int)Math.Ceiling(remaining.TotalMinutes)} min")})"
                : Strings.Get("Tray_Resume");
            menu.Items.Add(new ToolStripMenuItem(caption, null, (_, _) => _app.ResumeCapture()));
        }
        else
        {
            var pause = new ToolStripMenuItem(Strings.Get("Tray_Pause"));
            pause.DropDownItems.Add(Strings.Get("Tray_Pause5"), null, (_, _) => _app.PauseCapture(TimeSpan.FromMinutes(5)));
            pause.DropDownItems.Add(Strings.Get("Tray_Pause30"), null, (_, _) => _app.PauseCapture(TimeSpan.FromMinutes(30)));
            pause.DropDownItems.Add(Strings.Get("Tray_PauseUntilResume"), null, (_, _) => _app.PauseCapture(null));
            menu.Items.Add(pause);
        }
        menu.Items.Add(new ToolStripMenuItem(Strings.Get("Tray_SkipNext"), null, (_, _) => _app.Capture.SkipNextCopy = true));
        var notSaved = _app.Capture.NotSavedToday;
        if (notSaved > 0)
        {
            menu.Items.Add(new ToolStripSeparator());
            var text = notSaved == 1 ? Strings.Get("Tray_NotSavedOne") : Strings.Format("Tray_NotSaved", notSaved);
            menu.Items.Add(new ToolStripMenuItem(text) { Enabled = false });
        }
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(Strings.Get("Tray_ClearHistory"), null, (_, _) => _app.ConfirmClearHistory()));
        menu.Items.Add(new ToolStripMenuItem(Strings.Get("Tray_Settings"), null, (_, _) => _app.OpenSettings(0)) { ShortcutKeyDisplayString = "Ctrl+," });
        menu.Items.Add(new ToolStripMenuItem(Strings.Get("Tray_About"), null, (_, _) => _app.OpenSettings(4)));
        menu.Items.Add(new ToolStripMenuItem(Strings.Get("Tray_Quit"), null, (_, _) => _app.Quit()));
    }

    private static System.Drawing.Icon? LoadIcon()
    {
        try
        {
            using var stream = typeof(TrayIcon).Assembly.GetManifestResourceStream("Nori.Windows.Assets.nori.ico");
            return stream is null ? null : new System.Drawing.Icon(stream, 32, 32);
        }
        catch (Exception e)
        {
            Log.Warn($"tray icon could not be loaded: {e.Message}");
            return null;
        }
    }

    /// <summary>A washed-out copy of the icon for the paused state.</summary>
    private static System.Drawing.Icon? Dim(System.Drawing.Icon icon)
    {
        try
        {
            using var bitmap = icon.ToBitmap();
            using var dimmed = new System.Drawing.Bitmap(bitmap.Width, bitmap.Height);
            using (var graphics = System.Drawing.Graphics.FromImage(dimmed))
            {
                var matrix = new System.Drawing.Imaging.ColorMatrix(
                [
                    [0.3f, 0.3f, 0.3f, 0, 0],
                    [0.59f, 0.59f, 0.59f, 0, 0],
                    [0.11f, 0.11f, 0.11f, 0, 0],
                    [0, 0, 0, 0.55f, 0],
                    [0, 0, 0, 0, 1],
                ]);
                using var attributes = new System.Drawing.Imaging.ImageAttributes();
                attributes.SetColorMatrix(matrix);
                graphics.DrawImage(bitmap, new System.Drawing.Rectangle(0, 0, bitmap.Width, bitmap.Height), 0, 0, bitmap.Width, bitmap.Height, System.Drawing.GraphicsUnit.Pixel, attributes);
            }
            return System.Drawing.Icon.FromHandle(dimmed.GetHicon());
        }
        catch (Exception)
        {
            return null;
        }
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        _normal?.Dispose();
        _paused?.Dispose();
    }
}
