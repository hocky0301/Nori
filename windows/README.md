# Nori for Windows

The Windows build of Nori. Same product as the macOS app — a clipboard history where every copy is shown as
what it is — rewritten natively in C# / WPF, because the macOS app is Swift.

Requires **Windows 10 20H2 or later** (Windows 11 gets the acrylic panel background and rounded corners).

## Layout

| Project | What it is |
|---|---|
| `Nori.Core` | Platform-neutral logic: kind detection, secret detection, the capture decision, search, sections, the action grammar, the hint bar, the history store and the sensitive vault. No Windows types — it builds and tests on macOS and Linux. |
| `Nori.Core.Tests` | xUnit suites ported from the macOS test suite (179 tests). |
| `Nori.Windows` | The WPF app: tray icon, global hotkey, clipboard listener, SQLite storage, the panel, settings and the welcome flow. |

Nori.Core is a straight port of the Swift logic, so both platforms classify a copy, detect a secret and rank a
search the same way. The tests were ported with it, case for case.

## Build

```powershell
dotnet build windows/Nori.sln -c Release
dotnet test  windows/Nori.Core.Tests
dotnet run   --project windows/Nori.Windows -- --open
```

The solution also builds on macOS and Linux (`EnableWindowsTargeting`), which is how the app is developed
alongside the Swift version; only running it needs Windows.

## Keyboard

| Key | Action |
|---|---|
| Ctrl+Shift+V | Open / close Nori (Ctrl+Alt+V and Ctrl+` are offered in Settings) |
| type | Search |
| Enter | Paste the selected clip |
| Shift+Enter · Alt+Enter · Ctrl+Enter | Paste as plain text · paste and keep Nori open · copy only |
| Ctrl+1 … Ctrl+9 | Paste clip n (Shift / Alt stack) |
| ↑ ↓ · Home End · PgUp PgDn | Move · jump |
| Tab / Shift+Tab | Next / previous filter |
| Space · Ctrl+Y | Expand the selected card |
| Ctrl+P · Del · Ctrl+Z | Pin · delete · undo delete |
| Ctrl+O · Ctrl+R | Open link or file · reveal in Explorer |
| Ctrl+Shift+P · Ctrl+, · Esc | Pause capture · settings · close |

Where macOS reads privacy markers from the pasteboard, Windows has its own: Nori honours
`ExcludeClipboardContentFromMonitorProcessing` and `CanIncludeInClipboardHistory`, so password managers that
ask to be left out are left out.

## How it is verified

The app cannot run on the machine it is developed on, so it renders itself instead. Every launch flag below is
used by CI (`.github/workflows/windows.yml`), which uploads one PNG per state as an artifact:

```powershell
Nori.exe --state default --screenshot shots/default.png
```

| Flag | Effect |
|---|---|
| `--in-memory` | SQLite in memory; the real history is never touched |
| `--seed-demo` | A fixed set of demo clips (link, command, color, code, prose, image, file, a masked secret) |
| `--state <name>` | `default`, `search:swift`, `filter:code`, `cmd`, `shift`, `expanded:4`, `ghost`, `empty`, `dark`, `settings`, `onboarding` |
| `--screenshot <path>` | Render that state to a PNG and exit (implies `--in-memory --seed-demo`, English, frozen clock) |
| `--open` | Open the panel right after launch |

The frozen clock keeps relative times ("2m", "1h") identical between runs, so the images only change when the
UI does.
