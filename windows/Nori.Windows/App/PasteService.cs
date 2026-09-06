using System.Runtime.InteropServices;
using Nori.Windows.Native;

namespace Nori.Windows;

/// <summary>
/// The paste pipeline's Win32 half: remember the foreground window before the panel steals focus,
/// give it back, and press Ctrl+V with SendInput (scan codes, so the target sees a real keystroke).
/// </summary>
internal static class PasteService
{
    public static IntPtr RememberForeground() => User32.GetForegroundWindow();

    /// <summary>True when the previous window is in front again (or was never a real window).</summary>
    public static bool RestoreForeground(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !User32.IsWindow(hwnd)) return false;
        if (User32.IsIconic(hwnd)) User32.ShowWindow(hwnd, User32.SW_RESTORE);
        if (User32.SetForegroundWindow(hwnd) && User32.GetForegroundWindow() == hwnd) return true;

        // Windows refuses SetForegroundWindow unless our thread owns the foreground; attaching to the
        // target's input queue is the documented workaround.
        var targetThread = User32.GetWindowThreadProcessId(hwnd, out _);
        var ourThread = Kernel32.GetCurrentThreadId();
        var attached = targetThread != 0 && targetThread != ourThread && User32.AttachThreadInput(ourThread, targetThread, true);
        try
        {
            User32.BringWindowToTop(hwnd);
            User32.SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attached) User32.AttachThreadInput(ourThread, targetThread, false);
        }
        return User32.GetForegroundWindow() == hwnd;
    }

    /// <summary>
    /// Presses Ctrl+V. Modifiers the user still holds from the chord (Shift, Alt, Win) are released
    /// first so the target does not see Ctrl+Shift+V or Ctrl+Alt+V.
    /// </summary>
    public static bool SendCtrlV()
    {
        var inputs = new List<User32.INPUT>();
        foreach (var key in new ushort[] { User32.VK_SHIFT, User32.VK_MENU, User32.VK_LWIN, User32.VK_RWIN })
        {
            if (User32.IsKeyDown(key)) inputs.Add(Key(key, up: true));
        }
        inputs.Add(Key(User32.VK_CONTROL, up: false));
        inputs.Add(Key(User32.VK_V, up: false));
        inputs.Add(Key(User32.VK_V, up: true));
        inputs.Add(Key(User32.VK_CONTROL, up: true));
        var sent = User32.SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<User32.INPUT>());
        if (sent != inputs.Count)
        {
            Log.Warn($"SendInput sent {sent}/{inputs.Count} events (error {Marshal.GetLastWin32Error()})");
            return false;
        }
        return true;
    }

    private static User32.INPUT Key(ushort virtualKey, bool up)
    {
        var scan = (ushort)User32.MapVirtualKeyW(virtualKey, User32.MAPVK_VK_TO_VSC);
        return new User32.INPUT
        {
            type = User32.INPUT_KEYBOARD,
            ki = new User32.KEYBDINPUT
            {
                wVk = virtualKey,
                wScan = scan,
                dwFlags = (up ? User32.KEYEVENTF_KEYUP : 0) | (scan != 0 ? User32.KEYEVENTF_SCANCODE : 0),
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            },
        };
    }
}
