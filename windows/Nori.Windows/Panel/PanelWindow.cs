using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Nori.Core;
using Nori.Windows.Native;

namespace Nori.Windows.Panel;

/// <summary>
/// The frameless, topmost tool window that hosts the panel. Chrome only: acrylic on Windows 11
/// (solid fallback elsewhere), rounded corners, placement in physical pixels, key/deactivate events.
/// </summary>
internal sealed class PanelWindow : Window
{
    private readonly Border _root;
    private bool _acrylic;
    private bool _chromeApplied;

    public event Action<KeyEventArgs>? KeyPressed;
    public event Action<KeyEventArgs>? KeyReleased;
    public event Action? PanelDeactivated;

    public PanelWindow(Theme theme, bool allowAcrylic)
    {
        Theme = theme;
        AllowAcrylic = allowAcrylic;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Background = Brushes.Transparent;
        AllowsTransparency = false;
        Title = "Nori";
        Width = PanelPlacement.Width;
        Height = PanelPlacement.MinHeight;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        FontFamily = Theme.UiFont;

        _root = new Border
        {
            CornerRadius = new CornerRadius(Ui.PanelRadius),
            BorderThickness = new Thickness(1),
            BorderBrush = theme.PanelBorder,
            Background = theme.PanelBackground,
            ClipToBounds = true,
        };
        Content = _root;

        PreviewKeyDown += (_, e) => KeyPressed?.Invoke(e);
        PreviewKeyUp += (_, e) => KeyReleased?.Invoke(e);
        Deactivated += (_, _) => PanelDeactivated?.Invoke();
        SourceInitialized += (_, _) => ApplyChrome();
    }

    public Theme Theme { get; private set; }
    public bool AllowAcrylic { get; }
    public Border Root => _root;

    public FrameworkElement? Body
    {
        get => _root.Child as FrameworkElement;
        set => _root.Child = value;
    }

    public void ApplyTheme(Theme theme)
    {
        Theme = theme;
        _root.BorderBrush = theme.PanelBorder;
        _root.Background = _acrylic ? theme.PanelTint : theme.PanelBackground;
        if (_chromeApplied)
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd != IntPtr.Zero) DwmApi.SetAttribute(hwnd, DwmApi.DWMWA_USE_IMMERSIVE_DARK_MODE, theme.IsDark ? 1 : 0);
        }
    }

    private void ApplyChrome()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero) return;
        _chromeApplied = true;

        // Tool window: no taskbar button, no Alt+Tab entry.
        var exStyle = User32.GetWindowLongW(hwnd, User32.GWL_EXSTYLE);
        User32.SetWindowLongW(hwnd, User32.GWL_EXSTYLE, exStyle | User32.WS_EX_TOOLWINDOW);

        DwmApi.SetAttribute(hwnd, DwmApi.DWMWA_USE_IMMERSIVE_DARK_MODE, Theme.IsDark ? 1 : 0);
        if (DwmApi.SupportsRoundedCorners)
        {
            DwmApi.SetAttribute(hwnd, DwmApi.DWMWA_WINDOW_CORNER_PREFERENCE, DwmApi.DWMWCP_ROUND);
        }

        _acrylic = false;
        if (AllowAcrylic && DwmApi.SupportsSystemBackdrop)
        {
            try
            {
                var margins = new DwmApi.MARGINS { cxLeftWidth = -1, cxRightWidth = -1, cyTopHeight = -1, cyBottomHeight = -1 };
                DwmApi.DwmExtendFrameIntoClientArea(hwnd, ref margins);
                if (DwmApi.SetAttribute(hwnd, DwmApi.DWMWA_SYSTEMBACKDROP_TYPE, DwmApi.DWMSBT_TRANSIENTWINDOW)
                    && HwndSource.FromHwnd(hwnd) is { CompositionTarget: { } target })
                {
                    target.BackgroundColor = Colors.Transparent;
                    _acrylic = true;
                }
            }
            catch (Exception e)
            {
                Log.Warn($"acrylic backdrop unavailable: {e.Message}");
                _acrylic = false;
            }
        }
        _root.Background = _acrylic ? Theme.PanelTint : Theme.PanelBackground;
        TextOptions.SetTextRenderingMode(_root, _acrylic ? TextRenderingMode.Grayscale : TextRenderingMode.Auto);
    }

    /// <summary>Shows the panel at a rectangle given in physical pixels on a monitor with the given scale.</summary>
    public void ShowAt(PanelRect physical, double scale)
    {
        Width = physical.Width / scale;
        Height = physical.Height / scale;
        Left = physical.X / scale;
        Top = physical.Y / scale;
        var helper = new WindowInteropHelper(this);
        var hwnd = helper.EnsureHandle();
        User32.SetWindowPos(hwnd, User32.HWND_TOPMOST, (int)physical.X, (int)physical.Y, (int)physical.Width, (int)physical.Height, User32.SWP_NOACTIVATE);
        Show();
        Activate();
        // WPF may have re-applied its DIP position with a different DPI assumption; pin the pixel rect.
        User32.SetWindowPos(hwnd, User32.HWND_TOPMOST, (int)physical.X, (int)physical.Y, (int)physical.Width, (int)physical.Height, User32.SWP_NOACTIVATE);
    }

    public void HidePanel()
    {
        if (IsVisible) Hide();
    }

    /// <summary>Renders the panel's root visual to a PNG at the window's DPI (used by --screenshot).</summary>
    public void RenderPng(string path, double scale)
    {
        var width = _root.ActualWidth > 0 ? _root.ActualWidth : Width;
        var height = _root.ActualHeight > 0 ? _root.ActualHeight : Height;
        if (_root.ActualWidth <= 0)
        {
            // Never shown (headless fallback): lay the tree out off-screen.
            _root.Measure(new Size(width, height));
            _root.Arrange(new Rect(0, 0, width, height));
            _root.UpdateLayout();
        }
        RenderVisual(_root, width, height, scale, path);
    }

    public static void RenderVisual(FrameworkElement visual, double width, double height, double scale, string path)
    {
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(width * scale), (int)Math.Ceiling(height * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        using var stream = File.Create(path);
        encoder.Save(stream);
    }
}
