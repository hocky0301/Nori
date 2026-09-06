> **状態: Windows 版の設計指示書（2026-09-05）。実装が優先されます。**
>
> 実装との既知の差分:
> - .NET 8 と書いてあるが実装は **.NET 10**（`net10.0` / `net10.0-windows10.0.19041.0`）。
> - サイクルモード（ショートカット押しっぱなしで送る）は**未実装**。ホットキーは開閉トグルのみ。
> - 設定タブは Look を General に統合して **4 つ**。
> - `Nori.slnx` ではなく `Nori.sln`。

# Nori for Windows — build brief

Nori for macOS (Swift/SwiftUI, repo root) cannot run on Windows. This is a separate native Windows app that shares the
product design (NORI_SPEC.md) and the classification/privacy rules, with Windows-appropriate mechanics.

## Stack and layout (fixed)
- C# 12, .NET 8 (LTS). No Electron, no web view.
- `windows/Nori.sln`
  - `windows/Nori.Core/` — net8.0 class library, platform-neutral: ClipKind, ClipDraft/ClipRow (records), KindDetector (link/color/code
    rules ported 1:1 from Nori/Model/KindDetector.swift), SecretDetector (same regexes + Luhn, same mask), ClipClassifier decision
    order (ported from Nori/Clipboard/ClipClassifier.swift, using an abstract `PasteboardSnapshot`-like record of format→bytes),
    ContentHash (SHA-256 over stable formats), HistorySearch (tokenised AND substring + subsequence fallback + highlight ranges),
    PanelSections (Pinned/Today/Yesterday/Earlier/Results + positional numbers 1–9), ActionGrammar (Enter pastes; Shift=plain,
    Alt=keep open, Ctrl=copy only; number row ignores Ctrl), HintBarModel (Windows glyph text: "Enter", "Shift+Enter", "Alt+Enter",
    "Ctrl+Enter", "Space", "Ctrl+P", "Del", "Ctrl+1–9"), SensitiveVault (10-min TTL), relative time formatter.
  - `windows/Nori.Core.Tests/` — xUnit; must run on macOS/Linux with `dotnet test`. Port the Swift tests' cases (KindDetector,
    SecretDetector positives/negatives, classifier decisions, search ranking, sections/numbering, ActionGrammar truth table,
    HintBar strings, vault TTL).
  - `windows/Nori.Windows/` — net8.0-windows WPF app (`<UseWPF>true</UseWPF>`, `<UseWindowsForms>true</UseWindowsForms>` only for
    NotifyIcon, `<EnableWindowsTargeting>true</EnableWindowsTargeting>` so it compiles on macOS, `<Nullable>enable`,
    `<ImplicitUsings>enable`, `<ApplicationIcon>` from a generated .ico, `<SatelliteResourceLanguages>en;ja`). Single-instance mutex.
    Packages allowed: Microsoft.Data.Sqlite (storage). Nothing else.
- Native interop isolated in `windows/Nori.Windows/Native/*.cs` (P/Invoke: RegisterHotKey/UnregisterHotKey, AddClipboardFormatListener,
  GetForegroundWindow/SetForegroundWindow/GetWindowThreadProcessId/AttachThreadInput, SendInput, DwmSetWindowAttribute,
  GetClipboardOwner, QueryFullProcessImageName, SHGetFileInfo/ExtractAssociatedIcon).

## Behaviour (Windows mechanics)
- Tray icon (NotifyIcon): left click toggles the panel under the cursor; right click menu: Open Nori (hotkey text), Pause Capture ▸
  5 min / 30 min / Until I resume (or Resume Capture), Skip Next Copy, "N items not saved today" (disabled, hidden when 0),
  Clear History…, Settings…, About Nori, Quit Nori.
- Global hotkey default **Ctrl+Shift+V** (alternatives in Settings: Ctrl+Alt+V, Ctrl+`). Hotkey while the panel is open closes it.
  Cycle mode (hold Ctrl+Shift, tap V again to step, release to paste) if feasible via WM_HOTKEY repeats + GetAsyncKeyState polling;
  otherwise leave it out and say so.
- Capture: WM_CLIPBOARDUPDATE via AddClipboardFormatListener (Windows has real notifications — no polling). Read on the UI thread with
  retries (clipboard can be locked): text (CF_UNICODETEXT), "HTML Format", "Rich Text Format", PNG or CF_DIB (convert to PNG),
  CF_HDROP (files). Honour Windows' own privacy markers: formats "ExcludeClipboardContentFromMonitorProcessing" → concealed (ghost row
  "Concealed item from <app> wasn't saved"), "CanIncludeInClipboardHistory" == 0 → concealed, "CanUploadToCloudClipboard" ignored.
  Source app = process of GetClipboardOwner() (exe name + display name + icon). Ignore list by exe name (defaults: 1Password.exe,
  Bitwarden.exe, KeePassXC.exe, KeePass.exe, Dashlane.exe, LastPass.exe). Regex ignore list. Size caps identical to the spec.
  Own writes are tagged with a private format "Nori.Item" (payload: item GUID) → promote existing item instead of re-capturing.
- Secrets: SecretDetector → SensitiveVault (memory only, masked "•••• •••• •••• 1111 · Expires in 8m", pasteable, not searchable,
  not pinnable). Ghost rows max 5, cleared when the panel closes after having been shown.
- Storage: SQLite `%LOCALAPPDATA%\Nori\history.db` (items + representations table with BLOB; PNG only for images; inline thumbnail
  ≤ 224 px). Dedup by content hash (bump copyCount/lastCopiedAt/keep pin). Max items 500 (pinned exempt), expiry days, undo delete
  (single level, 4 s).
- Panel window: WPF, WindowStyle=None, ResizeMode=NoResize, Topmost, ShowInTaskbar=false, ToolWindow, 560×(75 % of work area,
  clamped 320–620) px at 100 % DPI (use DIPs). Windows 11 backdrop: DwmSetWindowAttribute DWMWA_SYSTEMBACKDROP_TYPE = 3 (transient/
  acrylic) + DWMWA_WINDOW_CORNER_PREFERENCE = 2 (round) + DWMWA_USE_IMMERSIVE_DARK_MODE per theme; Windows 10 fallback: solid
  theme background. Position modes: at cursor (default), center of the screen with the cursor, under the tray (bottom-right of the
  work area). The panel DOES activate (Windows needs focus for typing): remember `GetForegroundWindow()` before showing; closing on
  Deactivated. Paste pipeline: hide → SetForegroundWindow(previous) (with AttachThreadInput trick if refused) → SendInput Ctrl+V
  (key down Ctrl, V, up V, Ctrl; scan codes) → done. "Keep open" (Alt): paste, then re-show the panel at the same place with state kept.
  Copy-only (Ctrl): write clipboard, close (or toast "Copied" if keep open).
- UI (port NORI_SPEC.md §2–3 and §10 to WPF; keep it simple and readable): search box (placeholder "Search", always focused,
  ⋯ menu with Pause/Skip/Clear/Settings/About), 7 filter chips (All Text Links Code Colors Images Files; Tab / Shift+Tab cycle;
  zero-count chips dimmed), sections with headers, cards per kind: text (title + "3 lines · 412 chars · Rich text"), link (host bold +
  path), code (2 mono lines, Cascadia Mono/Consolas), color (swatch + #HEX + rgb()), image (56 px thumbnail + "1440 × 900 · PNG · 412 KB"),
  file (shell icon + name + folder), sensitive (red lock + mask + expiry), ghost (striped row, not selectable). Meta column: app icon,
  relative time, Ctrl+n keycap (brighter while Ctrl is held), pin star. Selected card: accent-tinted fill + thin accent border.
  Hover selects (ignored 150 ms after a key press). Click = paste (Shift/Alt/Ctrl bits), right-click context menu with the chords.
  Inline expanded preview (Space when search empty, Ctrl+Y always): text/code full (selectable), link full URL + Open, color big swatch
  + hex/rgb/hsl, image fitted, file paths + Reveal in Explorer (`explorer.exe /select,<path>`), meta strip. Hint bar at the bottom:
  resting = `Enter Paste · Shift+Enter Plain · Space Preview · Ctrl+P Pin · Del Delete` (keep it to five), Ctrl held = number row + Copy
  + Open/Reveal when applicable, Shift held = plain variants, Alt held = keep-open variants. Empty states: "Nothing copied yet" /
  "No matches for “…”" / "No links yet" etc. Toasts: "Deleted · Ctrl+Z to undo", "Copied", "Cleared N clips". Dark and light themes
  follow the system (AppsUseLightTheme registry) with semantic brushes; motion minimal (fade 120 ms). DPI-aware (PerMonitorV2).
- Keyboard: Enter/Shift+Enter/Alt+Enter/Ctrl+Enter, Ctrl+1–9 (+Shift/Alt), Up/Down, Ctrl+Up/Down or Home/End, PgUp/PgDn, Tab/Shift+Tab,
  Space (search empty) / Ctrl+Y, Ctrl+P, Del or Ctrl+Backspace delete, Ctrl+Z undo, Ctrl+O open, Ctrl+R reveal, Ctrl+Shift+P pause,
  Ctrl+, settings, Esc close, printable → search. IME: while composition is active (TextCompositionManager / e.Handled by IME),
  Enter confirms the composition and does not paste.
- Settings window (simple, five tabs or one scrolling page): General (hotkey picker among the 3 presets, start with Windows via
  HKCU\Software\Microsoft\Windows\CurrentVersion\Run, panel position), Capture (text/images/files, keep up to, forget older than,
  largest image), Privacy (ignored apps by exe with Add… file picker, mask secrets, ghost rows, clear on quit, storage used, Clear
  History…), Look (app icons, keycaps, hint bar), About (icon, version, GitHub link, "Inspired by Maccy", MIT, "No network access;
  clips never leave this PC"). First run: a small two-step welcome (hotkey → start with Windows) then open the panel with a seeded
  "Welcome to Nori 👋 Press Enter to paste this." clip. Do NOT mention any AI tooling anywhere.
- Localization: en (default) + ja via `Resources/Strings.resx` + `Strings.ja.resx`; all UI strings through the resource class.
- Verification without a Windows machine: command-line flags `--in-memory` (SQLite in memory), `--seed-demo` (same demo set as the
  Mac DebugBridge: link, command, color, code, prose, email, rgb(), slack text, git command, zenn.dev link pinned, a generated
  1440×900 gradient "window" PNG, a file (C:\Windows\explorer.exe), yesterday/earlier texts, one masked secret),
  `--screenshot <path>` (show the panel at the screen center, wait for layout, RenderTargetBitmap → PNG, exit 0) and
  `--state <name>` (default | search:swift | filter:code | cmd | shift | expanded:4 | ghost | empty | dark | settings | onboarding)
  to render each state for the CI artifact. Log to `%LOCALAPPDATA%\Nori\nori.log`.
- CI (`.github/workflows/windows.yml`): on push/PR: `dotnet test windows/Nori.Core.Tests` (ubuntu or windows), then on windows-latest
  `dotnet publish windows/Nori.Windows -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true`
  → zip `Nori-Windows-<version>.zip` (artifact), then a smoke step that runs the published exe with every `--state` and uploads
  `windows-screenshots` artifact (PNG per state). On tags `v*` the zip is attached to the GitHub release next to the Mac zip.
- Local checks on macOS: `dotnet build windows/Nori.sln` must succeed (EnableWindowsTargeting), `dotnet test windows/Nori.Core.Tests`
  must pass. The WPF app itself cannot run on macOS; rely on CI screenshots and read them.
