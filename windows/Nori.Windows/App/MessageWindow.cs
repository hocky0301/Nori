using System.Windows.Interop;
using Nori.Windows.Native;

namespace Nori.Windows;

/// <summary>
/// A message-only window that receives WM_HOTKEY (RegisterHotKey) and WM_CLIPBOARDUPDATE
/// (AddClipboardFormatListener). Both arrive on the UI thread through the WPF dispatcher.
/// </summary>
internal sealed class MessageWindow : IDisposable
{
    private const int HotkeyId = 0x4E4F; // "NO"
    private readonly HwndSource _source;
    private bool _hotkeyRegistered;
    private bool _listening;

    public event Action? HotkeyPressed;
    public event Action? ClipboardUpdated;

    public MessageWindow()
    {
        var parameters = new HwndSourceParameters("NoriMessageWindow")
        {
            WindowStyle = 0,
            ExtendedWindowStyle = 0,
            ParentWindow = User32.HWND_MESSAGE,
            Width = 0,
            Height = 0,
            PositionX = 0,
            PositionY = 0,
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    public IntPtr Handle => _source.Handle;

    public bool StartClipboardListener()
    {
        if (_listening) return true;
        _listening = User32.AddClipboardFormatListener(Handle);
        if (!_listening) Log.Error("AddClipboardFormatListener failed");
        return _listening;
    }

    /// <summary>Registers the chord (replacing any previous one); false when another app owns it.</summary>
    public bool RegisterHotkey(HotkeyPreset preset)
    {
        UnregisterHotkey();
        var (modifiers, key) = preset.Chord();
        _hotkeyRegistered = User32.RegisterHotKey(Handle, HotkeyId, modifiers | User32.MOD_NOREPEAT, key);
        if (!_hotkeyRegistered) Log.Warn($"RegisterHotKey failed for {preset.DisplayText()}");
        return _hotkeyRegistered;
    }

    public void UnregisterHotkey()
    {
        if (!_hotkeyRegistered) return;
        User32.UnregisterHotKey(Handle, HotkeyId);
        _hotkeyRegistered = false;
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        switch (msg)
        {
            case User32.WM_HOTKEY when wParam.ToInt32() == HotkeyId:
                handled = true;
                HotkeyPressed?.Invoke();
                break;
            case User32.WM_CLIPBOARDUPDATE:
                handled = true;
                ClipboardUpdated?.Invoke();
                break;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        UnregisterHotkey();
        if (_listening) User32.RemoveClipboardFormatListener(Handle);
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }
}
