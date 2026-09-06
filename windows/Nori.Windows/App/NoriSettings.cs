using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;
using Nori.Core;

namespace Nori.Windows;

internal enum HotkeyPreset
{
    CtrlShiftV = 0,
    CtrlAltV = 1,
    CtrlBacktick = 2,
}

internal static class HotkeyPresetExtensions
{
    public static string DisplayText(this HotkeyPreset preset) => preset switch
    {
        HotkeyPreset.CtrlAltV => "Ctrl+Alt+V",
        HotkeyPreset.CtrlBacktick => "Ctrl+`",
        _ => "Ctrl+Shift+V",
    };

    /// <summary>Modifier text used by the cycle-mode hint ("Release Ctrl+Shift to paste").</summary>
    public static string ModifierText(this HotkeyPreset preset) => preset switch
    {
        HotkeyPreset.CtrlAltV => "Ctrl+Alt",
        HotkeyPreset.CtrlBacktick => "Ctrl",
        _ => "Ctrl+Shift",
    };

    public static (uint Modifiers, uint VirtualKey) Chord(this HotkeyPreset preset) => preset switch
    {
        HotkeyPreset.CtrlAltV => (Native.User32.MOD_CONTROL | Native.User32.MOD_ALT, Native.User32.VK_V),
        HotkeyPreset.CtrlBacktick => (Native.User32.MOD_CONTROL, 0xC0 /* VK_OEM_3 (`~ on US layouts) */),
        _ => (Native.User32.MOD_CONTROL | Native.User32.MOD_SHIFT, Native.User32.VK_V),
    };
}

/// <summary>
/// User preferences, persisted as JSON in %LOCALAPPDATA%\Nori\settings.json. Nothing here changes
/// what a key does inside the panel. In screenshot mode the defaults are used and never written.
/// </summary>
internal sealed class NoriSettings
{
    public HotkeyPreset Hotkey { get; set; } = HotkeyPreset.CtrlShiftV;
    public PanelPosition PanelPosition { get; set; } = PanelPosition.Cursor;
    public bool CaptureText { get; set; } = true;
    public bool CaptureImages { get; set; } = true;
    public bool CaptureFiles { get; set; } = true;
    public int MaxItems { get; set; } = 500;
    public int ExpireAfterDays { get; set; }
    public int MaxImageMegabytes { get; set; } = 10;
    public List<string> IgnoredApps { get; set; } = [.. ClipboardFormats.DefaultIgnoredApps];
    public List<string> IgnoredFormats { get; set; } = [.. ClipboardFormats.DefaultIgnoredFormats];
    public List<string> IgnoreRegexes { get; set; } = [];
    public bool MaskSensitive { get; set; } = true;
    public bool ShowGhostRows { get; set; } = true;
    public bool ClearOnQuit { get; set; }
    public bool ShowAppIcons { get; set; } = true;
    public bool ShowKeycaps { get; set; } = true;
    public bool ShowHintBar { get; set; } = true;
    public bool HasCompletedOnboarding { get; set; }
    public int NotSavedCount { get; set; }
    public string NotSavedCountDay { get; set; } = string.Empty;

    [JsonIgnore]
    public string? Path { get; private set; }

    [JsonIgnore]
    public bool IsEphemeral => Path is null;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static NoriSettings Ephemeral() => new();

    public static NoriSettings Load()
    {
        var path = System.IO.Path.Combine(Log.DataDirectory, "settings.json");
        NoriSettings settings;
        try
        {
            settings = File.Exists(path)
                ? JsonSerializer.Deserialize<NoriSettings>(File.ReadAllText(path), JsonOptions) ?? new NoriSettings()
                : new NoriSettings();
        }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException)
        {
            Log.Error("settings.json could not be read; using defaults", e);
            settings = new NoriSettings();
        }
        settings.Path = path;
        settings.MaxItems = Math.Clamp(settings.MaxItems, 100, 2000);
        return settings;
    }

    public void Save()
    {
        if (Path is null) return;
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            File.WriteAllText(Path, JsonSerializer.Serialize(this, JsonOptions));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Log.Error("settings.json could not be written", e);
        }
    }

    public CapturePolicy ToCapturePolicy() => new()
    {
        IgnoredApps = new HashSet<string>(IgnoredApps, StringComparer.OrdinalIgnoreCase),
        IgnoredFormats = new HashSet<string>(IgnoredFormats, StringComparer.OrdinalIgnoreCase),
        IgnoreRegexes = IgnoreRegexes.Where(r => !string.IsNullOrWhiteSpace(r)).ToList(),
        CaptureText = CaptureText,
        CaptureImages = CaptureImages,
        CaptureFiles = CaptureFiles,
        MaskSensitive = MaskSensitive,
        MaxImageBytes = Math.Max(1, MaxImageMegabytes) * 1024 * 1024,
    };

    /// <summary>The "not saved today" counter, reset when the calendar day changes.</summary>
    public int NotSavedToday(DateTimeOffset now)
    {
        var day = now.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
        return NotSavedCountDay == day ? NotSavedCount : 0;
    }

    public void IncrementNotSaved(DateTimeOffset now)
    {
        var day = now.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
        if (NotSavedCountDay != day)
        {
            NotSavedCountDay = day;
            NotSavedCount = 0;
        }
        NotSavedCount++;
        Save();
    }

    // MARK: - Start with Windows (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)

    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "Nori";

    public static bool StartsWithWindows
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
                return key?.GetValue(RunValue) is string value && value.Length > 0;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }

    public static void SetStartsWithWindows(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
            if (key is null) return;
            if (enabled)
            {
                var exe = Environment.ProcessPath ?? System.Reflection.Assembly.GetExecutingAssembly().Location;
                key.SetValue(RunValue, $"\"{exe}\"");
            }
            else
            {
                key.DeleteValue(RunValue, throwOnMissingValue: false);
            }
        }
        catch (Exception e)
        {
            Log.Error("Run key could not be updated", e);
        }
    }
}
