using System.IO;
using System.Text;

namespace Nori.Windows;

/// <summary>A tiny append-only log at %LOCALAPPDATA%\Nori\nori.log (and stderr in screenshot mode).</summary>
internal static class Log
{
    private static readonly object Gate = new();
    private static string? _path;
    private static bool _echo;

    public static string DataDirectory
    {
        get
        {
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(local)) local = Path.GetTempPath();
            return Path.Combine(local, "Nori");
        }
    }

    public static void Initialize(bool echoToConsole)
    {
        _echo = echoToConsole;
        try
        {
            Directory.CreateDirectory(DataDirectory);
            _path = Path.Combine(DataDirectory, "nori.log");
            if (File.Exists(_path) && new FileInfo(_path).Length > 2_000_000)
            {
                File.Move(_path, Path.Combine(DataDirectory, "nori.previous.log"), overwrite: true);
            }
        }
        catch (Exception)
        {
            _path = null;
        }
    }

    public static void Info(string message) => Write("INFO", message);
    public static void Warn(string message) => Write("WARN", message);

    public static void Error(string message, Exception? exception = null) =>
        Write("ERROR", exception is null ? message : $"{message}: {exception}");

    private static void Write(string level, string message)
    {
        var line = $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff} [{level}] {message}";
        if (_echo)
        {
            try { Console.Error.WriteLine(line); } catch (IOException) { }
        }
        if (_path is null) return;
        lock (Gate)
        {
            try
            {
                File.AppendAllText(_path, line + Environment.NewLine, Encoding.UTF8);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }
}
