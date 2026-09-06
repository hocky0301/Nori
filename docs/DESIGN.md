> **状態: 設計の原典（2026-09-05）。実装が優先されます。**
>
> この文書は Nori v1 の設計判断をまとめたものです。実装後に意図的に変えた点があります
> （下記）。**コードと食い違う場合はコードが正**で、この文書は「なぜそうなっているか」を
> 読むために置いてあります。仕様に合わせてコードを"直す"前に、必ず下の差分を確認してください。
>
> | 項目 | この文書 | 実際の実装 | 理由 |
> |---|---|---|---|
> | Bundle ID | `app.nori.Nori` | `io.github.hocky0301.Nori` | ドメイン未取得 |
> | 自前ペーストボード型 | `app.nori.from-nori`（値は contentHash） | `io.github.hocky0301.Nori.item`（値は item の UUID） | UUID の方が復元が単純 |
> | App Sandbox | ON | **OFF** | Accessibility とファイル復元の都合。将来の課題 |
> | 画像 OCR | v1 では入れない | 実装済み・既定オフ（`ocrImages`） | 任意機能として同梱 |
> | あいまい検索 | 入れない | 部分列マッチを保持（substring より下位に並ぶ） | 打ち間違いに強い方が実用的 |
> | 設定タブ | General / Capture / Privacy / Look | **General / Capture / Privacy / About**（Look は General に統合） | 「もっとシンプルに」というユーザー要望 |
> | ヒントバー既定 | 7 チップ | **5 チップ**（⌥↩ と ⌘↩ は修飾キー押下時に表示） | 同上。日本語だと横幅も足りない |
> | ⌘1–9 の表示切替 | 設定で切替可 | 常時表示（設定を削除） | 同上 |
> | Windows 版 | 記載なし | `docs/WINDOWS_DESIGN.md` を参照 | 後から追加 |

# Nori v1 — Definitive Build Spec

Status: FINAL. This document supersedes the four proposals. Where they conflicted, the decision below is the decision. Maccy 2.7.1 paths are cited as `Maccy/...` for engineers who want the war story behind a rule.

Fixed constraints (not restated elsewhere): macOS 26+ only; Swift 6 strict concurrency; SwiftUI inside an AppKit non-activating `NSPanel`; SwiftData with `.externalStorage` blobs; only dependency `sindresorhus/KeyboardShortcuts`; `SMAppService` for login item; App Sandbox ON, hardened runtime, no network entitlement; bundle id `app.nori.Nori`; ~4–7k lines of Swift; everything verifiable by an agent.

---

## 1. Thesis and headline improvements

**Thesis.** Nori keeps Maccy's proven core — poll `NSPasteboard.changeCount`, a non-activating glass panel, paste via a synthesized ⌘V — and replaces everything above it. Every clip is rendered as what it is (text, link, code, color, image, file) on one sheet of Liquid Glass, and every key you can press is printed on screen the moment it applies. There is exactly one action grammar: Enter pastes, modifiers are orthogonal bits, and no preference can ever change what a key does.

**Five headline improvements over Maccy**

1. **Typed cards.** Six kinds with tailored anatomy, date sections, filter chips. Maccy: one 24 pt text row for everything (`Maccy/Views/ListItemView.swift`).
2. **One grammar, printed live.** ↩ pastes; ⇧ = plain, ⌥ = keep open, ⌘ = copy only; bits stack on click and ⌘1–9; a modifier-reactive hint bar and a chorded context menu show it. Maccy: a 12-case matrix driven by two preferences (`Maccy/HistoryItemAction.swift`).
3. **Stable numbers.** Pinned cards sit first, so a pin gets a permanent ⌘1…⌘n. Maccy: `HistoryItem.randomAvailablePin`.
4. **Visible privacy.** Likely secrets are masked, memory-only, expire in 10 minutes; concealed/oversized drops leave a content-free ghost row; pause has timers; password managers are ignored by default. Maccy: silent drops, `defaults write` to pause.
5. **Honest permissions.** Onboarding teaches by doing and seeds a "press ↩" clip; without Accessibility, ↩ visibly becomes Copy and the first hint chip is the fix. Maccy: `Accessibility.check()` is a no-op and "why doesn't it paste?" is FAQ #1.

---

## 2. Panel

| Property | Value |
|---|---|
| Window | `NSPanel`, styleMask `[.nonactivatingPanel, .fullSizeContentView]`, `isFloatingPanel`, `level = .screenSaver` (Chrome autofill is 999; Maccy #1403), `collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`, `canBecomeKey = true`, `animationBehavior = .none`, `backgroundColor = .clear`, `isOpaque = false`, `isMovable = false`, `resignKey → close()` unless a Nori sheet is up |
| Content view | `NSGlassEffectView(style: .regular)`, `cornerRadius = 22`, `tintColor = nil`, hosting an `NSHostingView` over the SwiftUI root. The ONLY glass surface in v1 (§10). |
| Width | 560 pt, fixed, not resizable |
| Height | Computed once per open: `H = clamp(floor(screen.visibleFrame.height × 0.75), 320, 620)`. Never changes while open — not on keystrokes, filter, expand, or empty state. The list scrolls inside. |
| Corner radius | 22 pt continuous |
| Panel created | once at launch, kept alive, hidden via `orderOut` |
| Position modes (`panelPosition`) | `cursor` (default): panel top-left corner at `NSEvent.mouseLocation`, then clamped into that screen's `visibleFrame` (Maccy `PopupPosition.constrained`). `center`: centered horizontally on the screen under the mouse, top edge at 22% of `visibleFrame.height` from the top. `statusItem`: top-left under the status item button. A status-item click ALWAYS uses `statusItem` regardless of the setting. |
| Appear | see §10 motion table; initial layer state (opacity 0, scale 0.97) is set BEFORE `orderFrontRegardless()` + `makeKey()` to avoid a first-frame flash |
| Not in v1 | caret-anchored position, window-center, last-position, remembered size, dragging the panel |

### 2.1 Wireframe (560 wide; heights in pt on the right)

```
╭────────────────────────────────────────────────────────────────╮  NSGlassEffectView .regular, r=22
│ (12 inset)                                                     │
│  ⌕  Search                                             ⏸  ⋯    │  36  SEARCH ROW   pill r=18, 14 pt text, always first responder
│ (8)                                                            │
│  [All]  Text  Links  Code  Colors  Images  Files               │  24  FILTER CHIPS r=12; Tab / ⇧Tab cycles; click selects
│ (8)                                                            │
│  PINNED                                                        │  16 above · 11 pt caps · 6 below   SECTION HEADER
│ ╭────────────────────────────────────────────────────────────╮ │
│ │ [{}]  ssh -i ~/.ssh/deploy ubuntu@10.0.2.14   ▣ 2h  ⌘1 ★  │ │  60  code card (2 mono lines)
│ │       -p 2222                                              │ │
│ ╰────────────────────────────────────────────────────────────╯ │ (4 gap)
│  TODAY                                                         │
│ ░░ Concealed item from 1Password wasn't saved ░░░░░░░░░░░░░░░░ │  32  GHOST ROW (no content, striped tertiary)
│ ╭────────────────────────────────────────────────────────────╮ │
│ │ [🔗]  developer.apple.com                     ◎ 2m  ⌘2     │ │  60  link card (host bold / path dim)
│ │       /design/human-interface-guidelines/liquid-glass      │ │
│ ╰────────────────────────────────────────────────────────────╯ │
│ ╭────────────────────────────────────────────────────────────╮ │
│ │ [██]  #FF6B35   rgb(255, 107, 53)             ✎ 5m  ⌘3     │ │  44  color card (swatch well)
│ ╰────────────────────────────────────────────────────────────╯ │
│ ╭────────────────────────────────────────────────────────────╮ │
│ │ ┌────┐ 1440 × 900 · PNG · 412 KB               ▣ 9m  ⌘4    │ │  76  image card (56×56 thumb)
│ │ │▒▒▒▒│                                                     │ │
│ │ └────┘                                                     │ │
│ ╰────────────────────────────────────────────────────────────╯ │
│ ╭────────────────────────────────────────────────────────────╮ │
│ │ [≡ ]  Meeting notes: the panel must never steal  ▤ 1h  ⌘5  │ │  60  text card (title / caption)
│ │       3 lines · 412 chars · Rich text                      │ │
│ ╰────────────────────────────────────────────────────────────╯ │
│ ╭────────────────────────────────────────────────────────────╮ │
│ │ [🔒]  •••• •••• •••• 4242 · Expires in 8m      ▣ 1m  ⌘6   │ │  44  sensitive card (in-memory only)
│ ╰────────────────────────────────────────────────────────────╯ │
│  YESTERDAY                                                     │
│ ╭────────────────────────────────────────────────────────────╮ │
│ │ [📄]  Invoice-2026-08.pdf                      ▤ 1d  ⌘7    │ │  60  file card (real Finder icon)
│ │       ~/Downloads · PDF document                           │ │
│ ╰────────────────────────────────────────────────────────────╯ │
│              … list scrolls; panel height never changes …      │
│ (8) ─────────────────── hairline .separator @ 0.5 ──────────── │
│  ↩ Paste  ⇧↩ Plain  ⌥↩ Keep open  ⌘↩ Copy  Space Preview  ⌘P Pin  ⌘⌫ Delete  │  28  HINT BAR
│ (12 inset)                                                     │
╰────────────────────────────────────────────────────────────────╯
```

Fixed chrome = 12+36+8+24+8 (top) + 8+28+12 (bottom) = 136 pt; at H = 620 the list area is 484 pt (about 7–8 cards).

---

## 3. Regions in detail

### 3.1 Search row (36 pt)
- `TextField`, 14 pt regular, placeholder "Search" in `.tertiary`; leading `magnifyingglass` 13 pt `.secondary`; pill fill `primary.opacity(0.06)`, r=18.
- Always first responder on open; cleared on every open; every printable character (no ⌘/⌃) goes here.
- Trailing: `ellipsis.circle` 16 pt `.secondary` at 50% opacity (100% on hover) → menu: Pause Capture ▸ (5 min / 30 min / Until I Resume), Skip Next Copy, Clear History…, Settings… ⌘,, About Nori. While paused a yellow `pause.fill` 12 pt sits left of it and the placeholder reads "Capture paused · 28:12" (countdown) or "Capture paused".
- IME rule: while `NSTextInputClient.hasMarkedText()` is true every key event passes through untouched (↩ confirms the conversion, never pastes). Maccy `Views/KeyHandlingView.swift`.
- Search: case-insensitive tokenised AND-substring match over `searchText` (title + link host + file names + source app name), tokens in any order, no throttle (in-memory `[ClipRow]`; timing logged with `os_signpost`, never asserted). A non-empty query collapses sections into ONE section "RESULTS" ranked by title-prefix match → earliest match index → `lastCopiedAt` desc. Sensitive items are never indexed. Highlight = accent background tint at 25% behind matched runs, never bold (bold shifts glyph widths and jitters the list).
- No matches with a non-empty query: ↩ pastes the typed text as plain text (Maccy `copyInMaccy`, made visible; §3.7).

### 3.2 Filter chips (24 pt)
Order, fixed: **All · Text · Links · Code · Colors · Images · Files**. No Pinned chip (pinned is a section). Selected chip: fill `.accent`, label white 12 pt semibold, r=12. Unselected: label `.secondary` 12 pt medium, no fill; hover `primary.opacity(0.06)`. A chip whose count is zero renders at 35% opacity but stays in place and remains selectable (layout never jumps). Tab / ⇧Tab cycles all seven; click selects. The active chip resets to All on every open. Filter and search compose. Filter applies to pinned items too.

### 3.3 List and card anatomy
`ScrollView` + `LazyVStack(spacing: 4)`; cards 536 wide; section headers 11 pt semibold `.secondary`, uppercase, tracking 0.4, 16 pt above / 6 below. Sections: **PINNED** (pinnedAt asc — oldest pin first, so numbers never shift) then **TODAY / YESTERDAY / EARLIER** by `lastCopiedAt` in the current calendar, desc within a section. Pinned items never appear in date sections; ghost rows sit at the top of TODAY; sensitive (in-memory) items merge into TODAY by capture time.

All cards share: padding 10 v / 12 h; r=12; leading **well** 28×28 r=7 (image: 56×56 thumbnail r=8, hairline stroke `primary.opacity(0.1)`); well → title gap 10; title block 13 pt SF Pro `.primary`, `.lineLimit(2)`, tail truncation; title → meta gap 8; **meta column** fixed 128 pt, right-aligned `HStack(spacing: 8)`: [app icon 16 pt, or `iphone` for Universal Clipboard] [relative time 11 pt medium `.secondary` tabular: "now", "2m", "1h", "1d", "Sep 3"] [keycap ⌘n] [`star.fill` 10 pt `.yellow` if pinned]. Keycaps: 11 pt medium, 18 pt tall, r=5, fill `primary.opacity(0.08)`, stroke `primary.opacity(0.12)`, min width 26, 50% opacity at rest, 100% while ⌘ is held (100 ms fade). Numbers 1–9 are positional over the visible list (pinned first, ghosts skipped, sensitive counted). Type tint appears ONLY inside the well: fill 12% of the tint, symbol 100%.

| Kind | Well | Title line 1 | Line 2 | Height |
|---|---|---|---|---|
| text | `text.alignleft`, gray (`.secondary`) | first non-empty line, whitespace collapsed | only if multi-line or rich: caption 12 pt `.secondary` "3 lines · 412 chars" + " · Rich text" when `isRichText` | 44 / 60 |
| link | `link`, `.blue` | host without `www.`, 13 pt semibold | path + query, 12 pt `.secondary`, middle-truncated | 60 |
| code | `chevron.left.forwardslash.chevron.right`, `.indigo` | first 2 lines SF Mono 12 pt, leading whitespace preserved, tab = 4 spaces | (part of the 2-line mono block) | 60 |
| color | 28×28 swatch of the color, r=7, hairline stroke, alpha over a checkerboard | normalized `#RRGGBB` (or `#RRGGBBAA`) uppercase, SF Mono 13 | none; `rgb(255, 107, 53)` follows on the same line in 12 pt `.secondary` | 44 |
| image | 56×56 thumbnail, aspect-fill | `1440 × 900 · PNG · 412 KB` | none | 76 |
| file | `NSWorkspace.shared.icon(forFile:)` 28 pt; 2+ files: first icon + "+2" badge | file name (or "3 files") | home-relative parent folder · UTType localized description, 12 pt `.secondary` | 60 |
| sensitive | `lock.shield`, `.red` | mask: all but the last 4 characters replaced by `•`, grouped in fours, SF Mono 13; then " · Expires in 8m" 12 pt `.secondary` | none | 44 |
| ghost | none; striped `tertiary` fill, r=8, 11 pt `.secondary` text | "Concealed item from 1Password wasn't saved" / "Image too large (48 MB) wasn't saved" | none | 32 |

Card states are in §10. Hover selects (moves the selection) except during the 150 ms after any key press, when hover is ignored. There is never a separate hover highlight on a non-selected card.

### 3.4 Pinned section
⌘P toggles `pinnedAt` (now / nil). Pinned items: exempt from item cap and expiry, first in the list, star in the meta column. Pin order = pin time; no reordering, no letters, no pin editor. Pinning inside RESULTS (search active) works and the card stays where it is until the search is cleared. Sensitive items cannot be pinned (⌘P does nothing; the context menu item is disabled).

### 3.5 Preview = inline expand
Trigger: Space (only when the search field is empty), ⌘Y (always). The selected card grows in place up to 280 pt; siblings shift; the panel does not resize. If the expanded card's bottom would fall below the visible list, scroll its top to the list top in the same animation; otherwise do not scroll. Space/⌘Y again, ↑/↓, or any selection change collapses it (Esc still closes the panel — one meaning); one card at a time; sensitive and ghost rows never expand.

| Kind | Expanded content |
|---|---|
| text | full text (≤ 10,000 chars, else truncated with "…" and "Showing first 10,000 characters") in a selectable, non-editable, scrollable `NSTextView`, SF Pro 13; rich text shown as plain text |
| code | same, SF Mono 12 |
| link | full URL wrapped in SF Mono 12, plus a button "Open ⌘O" |
| color | 88 pt swatch (r=12, checkerboard behind) + three lines SF Mono 12: `#FF6B35`, `rgb(255, 107, 53)`, `hsl(21, 100%, 60%)` — display only, no click-to-copy |
| image | image fitted into 536 × 220 max (downsampled decode, §6.7), caption "1440 × 900 · PNG · 412 KB" |
| file | every path, home-relative, one per line, SF Mono 12, plus "Reveal in Finder ⌘R" |

Every expanded card ends with a 16 pt meta strip, 11 pt `.secondary`: `Safari · first copied Sep 3, 14:02 · last Sep 5, 09:41 · copied 3×`.

### 3.6 Hint bar (28 pt) — exact strings
Chips are `keycap` + 11 pt `.secondary` verb, separated by 14 pt. Content is a pure function `HintBar.model(bits:caps:mode:)` (§5) and re-renders within 100 ms of any `flagsChanged`.

| State | Chips (left → right) |
|---|---|
| no modifiers | `↩ Paste` `⇧↩ Plain` `⌥↩ Keep open` `⌘↩ Copy` `Space Preview` `⌘P Pin` `⌘⌫ Delete` |
| ⌘ held | `⌘1–9 Paste item` `⌘↩ Copy` `⌘P Pin` `⌘Y Preview` `⌘O Open` `⌘⌫ Delete` `⌘⇧⌫ Clear…` |
| ⇧ held | `⇧↩ Paste as plain text` `⇧-click Same` `⇧⌘1–9 Paste item as plain text` |
| ⌥ held | `⌥↩ Paste and keep Nori open` `⌥-click Same` `⌥⌘1–9 Paste item, keep open` |
| ⌘⇧ held | `⇧⌘↩ Copy as plain text` `⇧⌘1–9 Paste item as plain text` |
| ⌘⌥ held | `⌥⌘↩ Copy, keep open` `⌥⌘1–9 Paste item, keep open` |
| ⇧⌥ (± ⌘) | first chip shows the stacked result, e.g. `⇧⌥↩ Paste plain, keep open` |
| cycle mode | `Release ⌘⇧ to paste` `↑↓ Move` `Esc Cancel` (modifier glyphs are the hotkey's actual modifiers) |
| Accessibility NOT trusted | first chip replaced by `↩ Copy · Enable pasting →` (`exclamationmark.triangle` 11 pt `.yellow`; the whole chip is clickable → `AXIsProcessTrustedWithOptions(prompt)` + open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`); all "Paste" verbs in every other state become "Copy" |
| `⌘O`/`⌘R` | only rendered when the selected card is a link/file (⌘O) or file (⌘R) |

`showHintBar = false` hides the bar; the panel height formula does not change (the list gets the space).

### 3.7 Empty and special states (rendered centered in the list area; panel height unchanged)
- No history: `doc.on.clipboard` 44 pt hierarchical `.secondary`; 15 pt semibold "Nothing copied yet"; 13 pt `.secondary` "Copy something in any app — it shows up here." with a keycap line "⌘⇧V opens Nori" (uses the live hotkey).
- No matches: `magnifyingglass` 32 pt; "No matches for “swift”"; "↩ pastes “swift” as text · ⌃U clears".
- Filter empty: "No links yet" / "No code yet" / "No colors yet" / "No images yet" / "No files yet" / "No text yet".
- Paused: search row shows `pause.fill` + countdown placeholder (§3.1); menu bar icon `appearsDisabled`.
- Accessibility drift banner (max once per calendar day, `accessibilityBannerLastShownAt`): 28 pt row under the search row, 12 pt: "Pasting needs Accessibility access · **Enable** · ✕". Shown on open when a paste attempt since the last open found `AXIsProcessTrusted() == false` and onboarding had recorded it as granted.
- Toasts: 4 s, bottom-center over the list, 12 pt on `primary.opacity(0.1)` capsule: "Deleted · ⌘Z to undo", "Copied", "Cleared 142 clips".

---

## 4. Item kind model

```swift
enum ClipKind: Int, Codable, CaseIterable { case text = 0, link, code, color, image, file }
```
Stored as an indexed Int. Detection runs ONCE at capture in the pure, nonisolated `ClipKind.detect(plainText:representations:sourceBundleID:) -> ClipKind`, never during scrolling. Rich text is a flag on `text`, not a kind.

Detection order, first match wins (`s` = plain text trimmed of whitespace/newlines):

| # | Kind | Rule |
|---|---|---|
| 1 | image | any of `public.png`, `public.tiff`, `public.jpeg`, `public.heic` present, OR Universal Clipboard item whose only payload is a `public.file-url` ending in `.jpeg`/`.jpg`/`.png` (read the bytes at capture, Maccy `universalClipboardImage`) |
| 2 | file | `public.file-url` present and not Universal-Clipboard text (Maccy `universalClipboardText` guard) |
| 3 | color | single line, ≤ 40 chars, matches `^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$` or `^rgba?\(\s*\d{1,3}%?\s*,\s*\d{1,3}%?\s*,\s*\d{1,3}%?\s*(,\s*(0|1|0?\.\d+))?\s*\)$` or `^hsla?\(\s*\d{1,3}(deg)?\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%\s*(,\s*(0|1|0?\.\d+))?\s*\)$` (case-insensitive). Parsed by our own ~40-line parser to an `NSColor` (no SwiftHEXColors). |
| 4 | link | single line, ≤ 2048 chars, `URL(string: s)` succeeds AND (scheme ∈ {http, https} with non-empty host) OR (scheme == mailto and the address contains `@`) |
| 5 | code | `s` has ≥ 2 lines AND score ≥ 3: +2 source bundle in editor/terminal set {com.apple.dt.Xcode, com.microsoft.VSCode, com.todesktop.230313mzl4w4u92 (Cursor), dev.zed.Zed, com.jetbrains.* (prefix), com.apple.Terminal, com.googlecode.iterm2, dev.warp.Warp-Stable, com.mitchellh.ghostty}; +2 ≥ 30% of non-empty lines start with a tab or ≥ 2 spaces; +1 count of characters in `{}();=<>` ≥ 1.5 × line count; +1 first line matches `^(\$ |#!/|import |from |func |def |class |struct |const |let |var |fn |package |use |#include|SELECT |<\?xml|<!DOCTYPE)`; +1 ≥ 2 lines end with `;` or `{`; −2 `isRichText` is true. Fixture corpus: 20 code / 20 prose samples must all classify correctly. |
| 6 | text | everything else (non-empty `s`). Whitespace-only strings without RTF/HTML are never stored. |

`isRichText` (flag on text/code): `public.rtf` present, decodes to a non-empty `NSAttributedString`, AND has ≥ 2 attribute runs. HTML alone never makes a clip rich (browsers always attach it).

**Stored representations per kind.** Everything not on the deny-list (§6.2) up to the per-type cap is stored, so private app types round-trip on paste. In practice: text → `public.utf8-plain-text` (+ `public.rtf`, `public.html`, private types); link/color/code → same as text; image → `public.png` only (§6.6) (+ private types); file → `public.file-url` (all items). Transient types (§6.4) are stored but excluded from the hash.

**Title and searchText.** `title` = first 1,000 characters of the previewable text: file → file names joined by ", "; image → "W × H · PNG · 412 KB"; color → normalized hex; otherwise plain text (or RTF/HTML string if no plain text). Card display collapses runs of whitespace and never shows `⏎`/`⇥` glyphs (Maccy `showSpecialSymbols` is dropped); `lineCount` and `charCount` are stored for the caption. `searchText` = lowercased title + link host + file names + localized source app name.

**Sensitive flag** (evaluated on `s` for kinds text/code/link, before storage; §6.5): matches create an in-memory `SensitiveClip` instead of a `ClipItem`.

**Model (SwiftData).**
```swift
@Model final class ClipItem {
  @Attribute(.unique) var id: UUID
  var kind: Int; var title: String; var searchText: String
  @Attribute(.unique) var contentHash: String          // hex SHA-256, indexed
  var sourceBundleID: String?; var sourceAppName: String?; var isUniversalClipboard: Bool
  var firstCopiedAt: Date; var lastCopiedAt: Date; var copyCount: Int; var pinnedAt: Date?
  var isRichText: Bool; var isTruncated: Bool; var lineCount: Int; var charCount: Int
  var byteSize: Int; var imageWidth: Int?; var imageHeight: Int?
  var thumbnail: Data?                                   // inline PNG ≤ ~40 KB
  @Relationship(deleteRule: .cascade) var representations: [Representation]
}
@Model final class Representation { var type: String; @Attribute(.externalStorage) var data: Data; var item: ClipItem? }
```
Views never hold `@Model` instances: `HistoryStore` (@MainActor, owns `ModelContainer.mainContext`) publishes `[ClipRow]` — Sendable value structs with everything a card needs (id, kind, title, caption, host/path, hex, thumbnail, app icon key, dates, pin, number). Expensive work (PNG transcode, thumbnail, hash) runs off-main on `Data` values inside `ClipPreparer` before insertion; SwiftData is touched only on the main actor. No `@ModelActor` in v1.

---

## 5. Keyboard and mouse map

Keys are matched on `keyCode` via a local `NSEvent` monitor (`.keyDown`, `.flagsChanged`), never on characters (`onKeyPress` cannot see key codes and breaks on JIS/AZERTY). Marked-text rule of §3.1 applies first. `NSApp.characterPickerWindow != nil` → navigation keys are ignored.

**ActionGrammar — single source of truth**, consumed by the key dispatcher, the click handler, the context menu, AND the hint bar renderer; unit-tested as an exhaustive truth table.
```swift
enum Base { case returnKey, click, number(Int) }
struct Bits: OptionSet { static let plain (⇧), keepOpen (⌥), copyOnly (⌘) }
struct Capabilities { var accessibilityTrusted: Bool }
enum Action { case paste(plain: Bool, keepOpen: Bool), copy(plain: Bool, keepOpen: Bool) }
static func resolve(_ base: Base, _ bits: Bits, _ caps: Capabilities) -> Action
```
Rules: `.number` ignores `copyOnly` (⌘ is the trigger; no copy-only variant of the number row). `paste` becomes `copy` with the same flags when `accessibilityTrusted == false`. Nothing in Settings feeds this function.

| Key | Action | When / notes |
|---|---|---|
| **⌘⇧V** (global, `KeyboardShortcuts.Name.openPanel`) | open panel (row 1 selected, search cleared, filter = All) / close if open | default; onboarding offers ⌘⇧C (Maccy) and ⌃⌥V one-click |
| hold hotkey modifiers, tap the key again | **cycle mode**: each tap selects the next row (wraps); ↑/↓ also move while held; releasing ALL modifiers pastes the selection (plain bits off) and closes | state machine `.closed → .opening → .toggle | .cycle` (Maccy `Observables/Popup.swift`): on hotkey key-down open + disable the KeyboardShortcuts handler; local monitor decides; re-enable on close. `cycleModeEnabled` off → hotkey is a plain toggle |
| Esc in cycle mode | close without pasting | |
| Esc | close, always, one press | ⌃U clears search instead |
| ↩ / keypad ⌤ | `resolve(.returnKey, bits)` on the selected row | no matches + non-empty query → paste the query as plain text (write only `public.utf8-plain-text`) |
| ⇧↩ / ⌥↩ / ⌘↩ and combinations | plain / keep open / copy only bits | keep open: see §7 step 6 |
| ⌘C | alias of ⌘↩ (copy only) | if the search field has a text selection, native copy wins |
| ⌘1 … ⌘9 | `resolve(.number(n), bits)` on visible row n | ⇧ and ⌥ stack; digits without ⌘ type into search |
| ↓ ↑ · ⌃N ⌃P · ⌃J | move selection (no wrap) | ⌃K = up unless row 1 is selected, then it deletes search text to end of line (Maccy #1055) |
| ⌘↓ ⌘↑ · ⌥↓ ⌥↑ · Home End · PgDn PgUp | last / first | |
| Tab / ⇧Tab | next / previous filter chip | |
| Space | toggle inline preview | ONLY when the search field is empty; otherwise types a space |
| ⌘Y | toggle inline preview | always. ⌃Space is never bound (IME input-source switch) |
| ⌘P | pin / unpin | disabled for sensitive rows |
| ⌘⌫ | delete selected row; selection moves to the next row (or previous at the end); toast "Deleted · ⌘Z to undo" | sensitive rows: removed from memory (no undo) |
| ⌘Z | undo the last delete within the 4 s toast window (single-level in-memory buffer; restores dates, pin, position) | |
| ⌘⇧⌫ | Clear History… confirmation sheet inside the panel (unpinned only); holding ⌥ in the sheet reveals "Also remove pinned" | ⌘⌥⇧⌫ opens the sheet with pinned included |
| ⌘O | link → open in default browser; file → open with default app; image → write PNG to a temp file and open in Preview | shown in hint bar only when applicable |
| ⌘R | file → `NSWorkspace.shared.activateFileViewerSelecting` | |
| ⌘F | focus search and select all its text | |
| ⌃U · ⌃W · ⌃H | clear search · delete word · delete char | |
| ⌘⇧P | pause capture until resumed / resume | |
| ⌘, | open Settings (activates the app for the Settings window only) | |
| ⌘Q | quit | |
| ⌘V | ignored inside the panel (people mash it) | |
| any printable | search field | |

**Mouse.** Hover selects (ignored for 150 ms after any key press). Click = `resolve(.click, bits from event)`: click pastes, ⇧-click plain, ⌥-click keep open, ⌘-click copy only. Right-click / ⌃-click = context menu listing the chord for every item: `Paste ↩` · `Paste as Plain Text ⇧↩` · `Paste and Keep Open ⌥↩` · `Copy ⌘↩` · — · `Preview Space` · `Pin/Unpin ⌘P` · — · link `Open in Browser ⌘O`; file `Open ⌘O`, `Reveal in Finder ⌘R`; image `Open ⌘O` · — · `Delete ⌘⌫`. Sensitive rows: Paste, Paste as Plain Text, Copy, Delete only; ghost rows: no menu. Keycaps and the star are part of the card, not separate targets. Clicking outside closes (`resignKey`). No drag-out, no drag-to-move.

---

## 6. Capture rules

### 6.1 Polling
`ClipboardMonitor` (@MainActor) runs a `Task` loop: read `NSPasteboard.general.changeCount`, `try await Task.sleep(for: .milliseconds(200))`. `ProcessInfo.processInfo.beginActivity(options: .background, reason: "Clipboard monitoring")` is held for the app's lifetime so App Nap cannot coalesce the loop (verify in Activity Monitor after 5 idle minutes). `checkForChanges()` also runs synchronously at the top of every panel open, so a copy made 50 ms before the hotkey is never missing. The interval is not user-facing; two copies inside one interval keep the last (documented).

### 6.2 The capture decision — a pure function
```swift
struct PasteboardSnapshot: Sendable { changeCount: Int; unionTypes: Set<String>; items: [[String: Data]]; sourceBundleID: String?; sourceAppName: String?; capturedAt: Date }
enum Decision: Sendable { case ignore; case ghost(GhostReason); case promote(marker: String); case storeSensitive(text: String, candidate: CaptureCandidate); case store(CaptureCandidate) }
static func evaluate(_ s: PasteboardSnapshot, settings: CaptureSettings, state: CaptureState) -> Decision
```
Steps, in order, first terminating step wins:
1. `changeCount` unchanged → `.ignore` (checked by the monitor before building a snapshot).
2. Paused (`pauseUntil` in the future or `.distantFuture`) or `skipNextCopy` → `.ignore`; `skipNextCopy` resets to false.
3. `unionTypes` contains Nori's marker `app.nori.from-nori` → `.promote(marker: value)` (value = the item's `contentHash`); no further checks (Maccy `.fromMaccy`).
4. `unionTypes` ∩ {`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `org.nspasteboard.AutoGeneratedType`} non-empty → Concealed: `.ghost(.concealed(app))`; Transient/AutoGenerated: `.ignore`. Checked on the UNION (Maccy #241).
5. `unionTypes` ∩ `ignoredPasteboardTypes` non-empty → `.ignore`. Default set: `Pasteboard generator type`, `com.agilebits.onepassword`, `com.typeit4me.clipping`, `de.petermaurer.TransientPasteboardType`, `net.antelle.keeweb`, `com.apple.pasteboard.promised-file-url`.
6. `sourceBundleID` ∈ `ignoredApps` → `.ignore`. Default: `com.1password.1password`, `com.agilebits.onepassword7`, `com.bitwarden.desktop`, `org.keepassxc.keepassxc`, `com.apple.keychainaccess`, `com.apple.Passwords`, `com.dashlane.Dashlane`. No "ignore all except listed" mode.
7. `com.apple.is-remote-clipboard` present and `captureUniversalClipboard == false` → `.ignore`; else flag `isUniversalClipboard`, source name "iPhone or iPad".
8. Merge all items into one candidate (BBEdit/Edge write two; Maccy #78/#472). Per item: skip if its string is whitespace-only and it has no non-empty RTF/HTML; drop types on the deny-list: prefix `dyn.`, prefix `com.microsoft.ole.source.`, and if both `com.microsoft.Link-Source` and `com.microsoft.ObjectLink` are present drop them plus `com.adobe.pdf` (Word bookmarks, #613/#770); drop storage classes the user disabled (`captureText` → utf8/rtf/html, `captureImages` → png/tiff/jpeg/heic, `captureFiles` → file-url). Nothing left → `.ignore`.
9. Any `ignoreRegexes` pattern matches the plain string → `.ignore`.
10. Size caps: `public.utf8-plain-text` > 2 MB → truncate to 2 MB and set `isTruncated`, drop rtf/html; any image type > `maxImageMegabytes` → `.ghost(.imageTooLarge(bytes))`; any other single representation > 1 MB → drop that representation only (kills 30 MB `com.apple.WebKit.custom-pasteboard-data` blobs).
11. Sensitive patterns (§6.5) match the plain text and `maskSensitive` → `.storeSensitive`.
12. Otherwise `.store(candidate)`.

`ClipPreparer.prepare(candidate) async -> PreparedClip` (nonisolated, off-main, pure over `Data`): image normalization (§6.6), kind detection, title/searchText, `contentHash`, thumbnail, dimensions, byteSize. `HistoryStore.commit(prepared)` on the main actor: dedup (§6.3), insert, enforce caps (§6.8), refresh `[ClipRow]`.

Not in v1: `IsSecureEventInputEnabled()` gate (Terminal/iTerm "Secure Keyboard Entry" keeps it on permanently), the `x.nspasteboard.ModifiedType` session-log replacement, the Chrome Remote Desktop / NetBeans activate-and-hide hack (documented limitation: those apps may need a manual ⌘V).

### 6.3 Dedup
`contentHash` = hex SHA-256 over representations sorted by type string, each contributing `type.utf8 + 0x00 + UInt64(data.count).littleEndian + data`, EXCLUDING transient types (§6.4). On commit, fetch by `#Predicate { $0.contentHash == hash }`: hit → keep `firstCopiedAt`, `copyCount += 1`, `lastCopiedAt = now`, keep `pinnedAt`, replace `sourceBundleID`; no new row. `.promote(marker)` does the same lookup by hash (also in the sensitive vault, resetting its TTL); if the hash is gone, fall through to normal capture with marker types stripped. Plain-only and rich variants of the same text are different hashes by design.

### 6.4 Transient types (stored, excluded from the hash)
`com.apple.linkpresentation.metadata`, `com.apple.WebKit.custom-pasteboard-data`, `org.chromium.web-custom-data`, `org.chromium.source-url`, `org.chromium.internal.source-rfh-token`, `com.apple.notes.richtext`, `x.nspasteboard.ModifiedType`, `org.nspasteboard.source`, `app.nori.from-nori`, `com.apple.is-remote-clipboard`.

### 6.5 Sensitive items (in memory only)
High-precision patterns only; no entropy heuristics (git SHAs, UUIDs, base64 blobs, SHA-256 digests must NOT match — the negative corpus has ≥ 40 such samples): `-----BEGIN [A-Z ]*PRIVATE KEY-----`, `\bAKIA[0-9A-Z]{16}\b`, `\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b`, `\bgithub_pat_[A-Za-z0-9_]{22,}\b`, `\bsk-[A-Za-z0-9_-]{32,}\b`, `\bxox[abpr]-[A-Za-z0-9-]{10,}\b`, `\bAIza[0-9A-Za-z_-]{35}\b`, `^eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}$` (whole string), and a 13–19 digit string (spaces/dashes allowed) that passes Luhn. `SensitiveClip` (struct in `SensitiveVault`, @MainActor) holds the representations, mask, source, `capturedAt`, `expiresAt = capturedAt + 10 min`; never written to SwiftData; excluded from search; un-pinnable; pasteable; removed by a 30 s sweep timer and on quit. A re-copy resets `expiresAt`. No "Keep" button, no ghost row for these.

### 6.6 Images
If `public.png` is present, drop `public.tiff` and `public.jpeg`/`public.heic`. If only TIFF (or only JPEG/HEIC), transcode to PNG off-main via `CGImageSource` → `CGImageDestination` and store PNG only (every screenshot arrives as a 30 MB TIFF + 300 KB PNG). Thumbnail: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 224`, `kCGImageSourceCreateThumbnailFromImageAlways = true`, `kCGImageSourceShouldCacheImmediately = false`, encoded as PNG and stored inline in `ClipItem.thumbnail` (typically 10–40 KB). The list never decodes a full image.

### 6.7 Preview decode
Expanded image cards decode with `CGImageSourceCreateThumbnailAtIndex` at `maxPixelSize = 536 × screen.backingScaleFactor` into an `NSCache<NSUUID, NSImage>` with `totalCostLimit = 64 MB` (cost = bytes per row × height). Cache is emptied on panel close.

### 6.8 Limits and hygiene
Unpinned item cap `maxItems` (default 500; pinned exempt), evicting oldest `lastCopiedAt` first, applied on every commit. Age expiry `expireAfterDays` (0 = never) applied on launch and hourly; pinned exempt. Store: `Application Support/Nori/History.store` inside the sandbox container; `ModelContainer` open failure → rename to `History.store.broken-<ISO8601>` (plus `-wal`/`-shm`) and create a fresh one, log at `.error`, show a one-time toast "History could not be opened and was reset". `clearOnQuit` deletes all unpinned on `applicationWillTerminate`. Clear History never touches the system pasteboard unless `clearSystemClipboardOnClear`.

### 6.9 Ghost rows and the not-saved count
`.ghost` decisions append a `GhostRow(reason, appName, at)` to an in-memory list (max 5, newest first) shown at the top of TODAY; all ghost rows are discarded when the panel closes after having been displayed. Every ghost increments `notSavedCount` for the current calendar day (persisted, reset at midnight) and the status menu shows "3 items not saved today". `showGhostRows = false` suppresses the rows but not the count. Ghost rows never carry content.

### 6.10 Own-write marker
Every pasteboard write by Nori adds `app.nori.from-nori` (string value = the clip's `contentHash`) and `org.nspasteboard.source` (= the clip's original `sourceBundleID`, so other tools see the true origin). Typed-text paste (§3.1) writes the marker with an empty value and is captured as a new text clip.

---

## 7. Paste pipeline

1. **Resolve**: `ActionGrammar.resolve(base, bits, Capabilities(accessibilityTrusted: AXIsProcessTrusted()))` — trust is re-read on every action (permission drift after rebuilds/updates).
2. **Record target**: the frontmost app at panel-open time is remembered for logging only; because the panel never activates Nori, the target app still owns the key window.
3. **Write** (`PastePerformer`, @MainActor): `pasteboard.clearContents()`; if `plain`: representations reduced to `public.utf8-plain-text` + all `public.file-url` items (Maccy #962; if there is no plain string, behave as if not plain); `public.file-url` representations are written via `writeObjects([NSPasteboardItem])` (multi-file paste works), all other types via `setData(_:forType:)` on the first item (mixing breaks rich text, Maccy `Clipboard.copy`); then the markers of §6.10.
4. **Copy-only** (`.copy`): if `keepOpen` show toast "Copied" and stay; else close the panel. Done. When the copy resulted from a degraded paste (untrusted), record `pasteBlockedByAccessibility = true` for the drift banner (§3.7).
5. **Paste** (`.paste`): close the panel (`orderOut`, reset state) → on the NEXT run-loop turn (`DispatchQueue.main.async`) post the keystroke: `CGEventSource(stateID: .combinedSessionState)` with `setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)`; `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with `flags = [.maskCommand]` plus the device-side bit `0x000008` (Flycut trick), post to `.cgSessionEventTap`; `Task.sleep(10 ms)`; post key-up.
6. **Keep open** (`⌥`): same as 5, then after 60 ms re-open the panel at the same frame with search, filter, scroll and selection preserved (a key HID-level ⌘V goes to the key window, which would be the panel if it stayed key — so it must resign first).
7. **Key code**: `KeyCodeResolver.commandV()` walks virtual key codes 0…50 through `UCKeyTranslate` with the current `TISCopyCurrentKeyboardLayoutInputSource` `kTISPropertyUnicodeKeyLayoutData` and modifier state `cmdKey >> 8`, returning the first code whose ⌘-layer character is `v` (handles QWERTY, JIS, AZERTY, Dvorak, "Dvorak – QWERTY ⌘" without Sauce; Maccy #482/#520); fallback `kVK_ANSI_V` (9). Cached per input-source change (`kTISNotifySelectedKeyboardInputSourceChanged`).
8. **Failure modes**: target ignores synthetic ⌘V (remote desktops, some VMs) → the clipboard already holds the clip; documented. Trust revoked → step 1 degrades to copy; banner next open.

**Accessibility onboarding copy (step 2 of onboarding; verbatim).**
- Title: **Let Nori paste for you**
- Body: "When you pick a clip, Nori presses ⌘V in the app you were using. macOS calls this permission Accessibility. Nori has no network access and stores clips only on this Mac."
- Primary button: **Open System Settings** → calls `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` then opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`; a 1 s timer polls `AXIsProcessTrusted()`; the status pill flips from "Not enabled" (gray) to "✓ Enabled" (green) live, no relaunch.
- Secondary link: **Skip for now** — caption: "Without it, ↩ copies the clip instead of pasting. You can turn this on later in Settings › General."

**Onboarding (regular activating window, 520 × 440, glass card, 3 dots; re-runnable from Settings › General).** Step 1 "**Nori keeps what you copy**": `KeyboardShortcuts.Recorder` pre-filled with ⌘⇧V; a temporary handler makes the card show "✓ That's it — this opens Nori anywhere" the moment the chord is pressed; caption "In Chrome and Slack, ⌘⇧V is 'paste and match style' — use ⇧↩ inside Nori instead, or pick ⌘⇧C"; one-click buttons ⌘⇧C and ⌃⌥V; on a system conflict the recorder's own message is shown and the alternatives highlighted; warn "This shortcut types a character, so it won't work in password fields" when `UCKeyTranslate` of the chord yields a printable character. Step 2: Accessibility (above). Step 3 "**Start at login?**": toggle (`SMAppService.mainApp`, shown ON so the choice is explicit) + **Done**. On Done: `hasCompletedOnboarding = true`, insert the seeded clip "Welcome to Nori 👋 Press ↩ to paste this." directly into the store (`sourceAppName = "Nori"`, system pasteboard untouched), then open the panel with it selected.

---

## 8. Settings window

SwiftUI `Settings` scene, toolbar-style `TabView`, 520 pt wide, `.formStyle(.grouped)`. Opening Settings activates the app (the only time Nori activates). All keys are `UserDefaults.standard` via `@AppStorage` unless noted. No control anywhere changes what a key does.

**General** (`gearshape`)

| Label | Control | Default | Key |
|---|---|---|---|
| Open Nori | `KeyboardShortcuts.Recorder` | ⌘⇧V | `KeyboardShortcuts.Name.openPanel` |
| Hold the modifiers and tap the key again to step through clips | Toggle | on | `cycleModeEnabled` |
| Start Nori when I log in | Toggle | off | `SMAppService.mainApp` status (no defaults key) |
| Show the panel | Popup: At the mouse pointer / Center of screen / Under the menu bar icon | At the mouse pointer | `panelPosition` = `cursor` / `center` / `statusItem` |
| Show icon in the menu bar (caption: "Without it, open Settings with ⌘, inside the panel") | Toggle | on | `showMenuBarIcon` |
| Pasting | status row: "✓ Enabled" or "Not enabled — Open System Settings" (same flow as onboarding) | — | — |
| Show welcome again | Button | — | resets `hasCompletedOnboarding` |

**Capture** (`tray.and.arrow.down`)

| Label | Control | Default | Key |
|---|---|---|---|
| Remember: Text / Images / Files | 3 toggles | on / on / on | `captureText`, `captureImages`, `captureFiles` |
| Keep up to | Stepper 100–2000, step 100, suffix "clips" (pinned don't count) | 500 | `maxItems` |
| Forget clips older than | Popup: Never / 1 day / 1 week / 1 month (pinned exempt) | Never | `expireAfterDays` = 0 / 1 / 7 / 30 |
| Largest image to keep | Popup: 5 / 10 / 25 / 50 MB | 10 | `maxImageMegabytes` |
| Include copies from my iPhone and iPad | Toggle | on | `captureUniversalClipboard` |
| ▸ Advanced: Ignored pasteboard types | editable list (+/−, restore defaults) | §6.2 step 5 set | `ignoredPasteboardTypes` ([String]) |
| ▸ Advanced: Skip text matching these patterns | regex list (+/−; invalid regex shown in red and ignored) | empty | `ignoreRegexes` ([String]) |

**Privacy** (`lock.shield`)

| Label | Control | Default | Key |
|---|---|---|---|
| Don't remember copies from | app list (+ opens an app picker from /Applications, −) | §6.2 step 6 list | `ignoredApps` ([String] bundle ids) |
| Hide things that look like passwords or API keys (caption: "Shown masked, never saved to disk, forgotten after 10 minutes") | Toggle | on | `maskSensitive` |
| Show a note in the list when something wasn't saved | Toggle | on | `showGhostRows` |
| Clear history when Nori quits | Toggle | off | `clearOnQuit` |
| ▸ Advanced: Clearing history also clears the system clipboard | Toggle | off | `clearSystemClipboardOnClear` |
| (static) "Clips are stored unencrypted in Nori's container in ~/Library. Use Pause for sensitive work." | text | — | — |
| Storage used | "12.4 MB · 342 clips · 3 pinned" (computed) | — | — |
| Clear History… (⌥ → Clear Including Pinned…) | Button + confirmation sheet | — | — |

**Look** (`paintpalette`)

| Label | Control | Default | Key |
|---|---|---|---|
| Show app icons on clips | Toggle | on | `showAppIcons` |
| Show ⌘1–⌘9 on clips | Toggle | on | `showKeycaps` |
| Show keyboard hints at the bottom of the panel | Toggle | on | `showHintBar` |

Internal keys (no UI): `hasCompletedOnboarding`, `accessibilityGrantedOnce`, `accessibilityBannerLastShownAt`, `pauseUntil` (Date; nil = running; `.distantFuture` = until resumed), `skipNextCopy`, `notSavedCount`, `notSavedCountDay`.

Deliberately absent (do not add): paste-by-default, remove-formatting-by-default, "Return key" / "When I choose a clip", search mode, sort by, pin position, pin letters, density, glass style, appearance override, preview delay, check-interval slider, thumbnail height, sounds, notifications, menu-icon variants, "show recent copy in menu bar", ignore-all-except, byte budget, secret TTL slider.

---

## 9. Status item, pause, login item

`NSStatusItem` with template symbol `doc.on.clipboard`; `button.appearsDisabled = true` while paused; `showMenuBarIcon = false` removes it (panel and ⌘, still work). Left-click: toggle the panel under the icon. ⌥-click: pause until resumed / resume. ⌥⇧-click: skip next copy (icon flashes once). Right-click or ⌃-click menu:

```
Open Nori                     ⌘⇧V   (live hotkey)
──────────
Pause Capture               ▸  For 5 Minutes / For 30 Minutes / Until I Resume
   (when paused the item becomes "Resume Capture" with caption "Paused · 28 min left")
Skip Next Copy
──────────
3 items not saved today          (disabled, hidden when 0)
──────────
Clear History…
Settings…                     ⌘,
About Nori
Quit Nori                     ⌘Q
```

Pause: `pauseUntil` timer; on expiry capture resumes silently and the icon un-dims; the countdown appears in the search placeholder and the menu caption. Launch at login: `SMAppService.mainApp.register()/unregister()`; the toggle reflects `.status` and reads "Enabled in System Settings" (disabled) on `.requiresApproval`. No notification permission is ever requested; no sounds.

---

## 10. Visual system

**Material.** One glass surface: the panel (`NSGlassEffectView .regular`). Cards, chips, keycaps, search pill, hint bar and toasts are flat fills over it. No `.glassEffect` anywhere in v1. Optional experiment AFTER everything is green, behind compile flag `NORI_GLASS_LENS`: a single `glassEffectID("selection")` inside a `GlassEffectContainer` as the selection; keep it only if a screenshot shows a clean morph inside `NSHostingView` + `LazyVStack`; otherwise the flat selection below stays.

**Typography** (SF Pro / SF Mono, fixed sizes, no Dynamic Type): card title 13 regular `.primary`; card secondary 12 regular `.secondary`; link host 13 semibold; code SF Mono 12; color hex SF Mono 13; meta 11 medium `.secondary` tabular numerals; section header 11 semibold `.secondary` uppercase tracking 0.4; keycap 11 medium; search 14 regular, placeholder `.tertiary`; hint bar 11 regular `.secondary`; toast 12 medium; empty title 15 semibold, body 13 `.secondary`; onboarding title 20 semibold, body 13; settings: system Form.

**Spacing tokens** (4 pt grid): `inset 12`, `rowGap 8`, `cardGap 4`, `cardPadV 10`, `cardPadH 12`, `wellSize 28`, `thumbSize 56`, `wellGap 10`, `metaGap 8`, `metaWidth 128`, `sectionAbove 16`, `sectionBelow 6`, `hintGap 14`, radii: panel 22, card 12, well 7, thumb 8, search 18, chip 12, keycap 5, ghost 8.

**Color roles** (semantic colors only; light / dark differ only in the opacity steps):

| Role | Light | Dark |
|---|---|---|
| Card ground normal | `primary.opacity(0.04)` | `0.06` |
| Card selected | `accent.opacity(0.22)` fill + 1 pt inside stroke `accent.opacity(0.35)`; text stays `.primary` (no white-on-accent) | `0.28` / `0.40` |
| Card pressed | scale 0.985 for 80 ms | same |
| Card expanded | ground `0.06` + 1 pt inside stroke `accent.opacity(0.3)` | `0.08` / `0.35` |
| Chip selected | `.accent` fill, white label | same |
| Search pill / keycap / toast | `primary.opacity(0.06)` / `0.08` / `0.10` | `0.08` / `0.10` / `0.14` |
| Ghost row | `tertiary` at 0.5 with 45° 2 pt stripes at `primary.opacity(0.05)` | same |
| Match highlight | `accent.opacity(0.25)` behind runs | `0.35` |
| Separator | `.separator` at 0.5 | same |

Kind tints (well only): text `.secondary`, link `.blue`, code `.indigo`, image (thumbnail; fallback `photo` `.teal`), file (real icon, no tint), color (the value), sensitive `.red`, Universal Clipboard meta icon `iphone` `.secondary`.

**Motion** (all durations ms; Reduce Motion column applies when `accessibilityReduceMotion`):

| Event | Animation | Reduce Motion |
|---|---|---|
| Panel appear | hosting-view layer: opacity 0→1 and scale 0.97→1, 160 ease-out, anchored at the position anchor; state set before `orderFront` | opacity only, 120 |
| Panel dismiss | opacity 1→0, 100 ease-out, then `orderOut` | same |
| Selection move | none (instant); list scrolls to keep the selection visible, no animation | same |
| Expand / collapse | `.spring(duration: 0.30, bounce: 0.15)` on height; content fades in over the last 120 | height 150 ease-out, no fade |
| New clip arrives while open | `.move(edge: .top)` + opacity, `.snappy` | opacity 150 |
| Filter / search change | cross-fade 120 | same |
| Hint bar modifier swap | cross-fade 100 | same |
| Keycap ⌘ brighten | opacity 0.5→1, 100 | same |
| Toast | in: opacity + 8 pt rise 150; out: opacity 200 after 4 s | opacity only |
| Delete / undo | row removal/insertion `.snappy` | opacity 150 |

Nothing else animates. No pin fly-to-section, no arrival pulse, no lens morph (unless the flag experiment passes).

---

## 11. Scope and test plan

**IN v1:** capture pipeline (§6) incl. ghost rows, sensitive vault, pause timers, PNG-only images, hash dedup, caps, expiry, store recovery; six kinds + rich flag; 560 pt glass panel with search, chips, four sections, cards per §3.3, inline expand, hint bar, keycaps, toasts, empty states, drift banner; full key map (§5), cycle mode, ActionGrammar, context menu, undo delete; paste pipeline with UCKeyTranslate, keep-open reopen, Accessibility degradation; status item + menu; Settings (4 tabs); onboarding (3 steps + seeded clip); launch at login; en + ja String Catalog; `--ui-testing` mode; unit tests below; GitHub Actions (build + test on macOS 26 runner, ad-hoc signed zip artifact); README with screenshots; MIT license crediting Maccy; Zenn article.

**NOT in v1 (explicit):** image OCR (v1.5, off by default); caret-anchored/window-center/last-position; resizable or movable panel; two-column or slide-out preview; content-fitting height; "This week" section; two-stage Esc; morphing glass lens as a requirement; pin reordering or letters; drag-out; ⌘/ cheat sheet; multi-select / paste stack; fuzzy or regex search; snippets/templates/transforms; color format conversion on copy; secure-input gate; representation allow-list; 10-second Keep staging; byte-budget eviction; sort-by; density; glass/appearance overrides; sounds/notifications; Sparkle; notarization and Homebrew cask (needs a human Developer ID); sync; Shortcuts/Intents; URL scheme; Touch Bar; menu-bar text of latest copy; alternative icons; localisation beyond en + ja; Chrome Remote Desktop / NetBeans hack.

**`--ui-testing` launch mode:** in-memory `ModelContainer`; injected `Clock` fixed at 2026-09-05 10:00 local; seeded fixtures: pinned code, link, color, image (fixture PNG 1440×900), rich 3-line text, file (`~/Downloads/Invoice-2026-08.pdf`), sensitive (`4111 1111 1111 1111`), ghost (concealed from "1Password"), one yesterday text, three earlier texts; `panelPosition = center`; `paste()` routed to a recording stub; `--open` opens the panel immediately; `--state=<name>` presets: `empty`, `nomatch`, `paused`, `untrusted`, `cycle`, `expanded:<kind>`, `filter:<kind>`, `mods:cmd|shift|opt`, `dark`. Signing: a stable ad-hoc identity with a fixed bundle id (`codesign -s - --force --timestamp=none`) because TCC Accessibility trust is bound to the signature. Screenshots come from external capture (`screencapture -l <windowID>` or computer-use `app_screenshot`), never an in-app flag.

**Unit tests (XCTest, no pasteboard access, deterministic):**
- `ActionGrammarTests` — exhaustive truth table: 3 bases × 8 bit combinations × trusted/untrusted; number row ignores copyOnly.
- `HintBarModelTests` — every row of §3.6 yields exactly those chip strings, incl. untrusted, cycle, ⌘O/⌘R visibility.
- `CaptureRulesTests` — fixture snapshots → `Decision`: 1Password concealed (ghost), transient, BBEdit two-item merge, Word trio stripped, `dyn.` dropped, whitespace-only skipped / kept with RTF, Universal Clipboard JPEG-as-file-URL → image, Universal Clipboard off, ignored app/type, regex, own marker → promote, paused, skip-next resets, 48 MB image → ghost, 30 MB WebKit blob dropped but clip kept, 3 MB text truncated, JWT/AKIA/ghp_/sk-/private key/Luhn → storeSensitive.
- `ClipKindDetectionTests` — 20 code / 20 prose; color regexes (alpha, percentages, invalid); links (http/https/mailto, no host, two lines, > 2048); file vs Universal Clipboard text; single-run RTF is not rich.
- `SecretPatternTests` — all positives; ≥ 40 negatives (git SHAs, UUIDs, SHA-256, base64, non-Luhn 16-digit, ISBNs).
- `ContentHashTests` / `DedupTests` — order independence, transient exclusion, promote preserves firstCopiedAt/copyCount/pinnedAt, plain vs rich distinct.
- `ImageNormalizationTests` — TIFF+PNG → PNG only; TIFF-only → PNG; thumbnail ≤ 224 px and ≤ 60 KB.
- `KeyCodeResolverTests` — each installed layout among QWERTY, JIS, AZERTY, Dvorak, Dvorak-QWERTY⌘ (via `TISCreateInputSourceList`, skipped if absent) resolves to a code yielding `v` on the ⌘ layer; fallback path.
- `SearchTests` — tokenised AND, ranking, highlight ranges, sensitive excluded; 2,000-row timing logged only.
- `SectionBucketingTests` — Today/Yesterday/Earlier across midnight and a timezone change; pinnedAt ordering; numbering skips ghosts.
- `CycleModeTests` — synthesized `NSEvent`s: `.opening → .cycle → paste`, `.opening → .toggle`, Esc cancel, ↑/↓ while held, `cycleModeEnabled` off.
- `SensitiveVaultTests`, `LimitsTests`, `UndoDeleteTests`, `StoreRecoveryTests` — TTL/reset/not searchable/not pinnable; cap evicts oldest unpinned only and expiry exempts pinned; undo within window only; corrupt store moved aside and a fresh one opens.
- `PastePerformerTests` — untrusted → copy path; plain strips rtf/html but keeps file URLs; marker + source types present; plain paste without a plain string keeps original types.
- `SettingsDefaultsTests` — default for every key in §8.

**Screenshot checklist (light AND dark, from `--ui-testing`):** default list; ⌘ held (bright keycaps + ⌘ hint bar); ⇧ held; ⌥ held; search "swift" with highlights + RESULTS; each of the 6 filter chips + an empty chip; expanded text / code / link / color / image / file; sensitive card; ghost row; empty history; no-match; paused; untrusted hint bar; drift banner; cycle-mode hint bar; delete toast; context menu; status menu; onboarding steps 1–3 (incl. conflict and ✓ states); Settings 4 tabs; panel at cursor / center / status-item positions.

---

## 12. Article angles (Zenn, ja)

1. **One grammar, two consumers.** Problem: Maccy's 12-case `HistoryItemAction` lets hints and behaviour drift and preferences flip key meanings → trick: a single `ActionGrammar.resolve(base, bits, caps)` feeds both the key dispatcher and the hint bar and is truth-table tested, so the hint bar can only print the truth.
2. **A pasteboard you can unit-test.** Problem: `NSPasteboard.general` is global, lazy, lying (union types, two-item copies, Word bookmarks, 30 MB WebKit blobs) → trick: freeze it into a `PasteboardSnapshot` value and make the 12-step capture decision a pure function tested against fixture snapshots.
3. **Pasting from a panel that never activates.** Problem: a non-activating `NSPanel` must own the keyboard for search yet the target app must receive a synthetic ⌘V whose key code depends on the live layout (JIS, Dvorak-QWERTY⌘) → trick: resign key, post `CGEvent` on the next run-loop turn with the code found by walking `UCKeyTranslate` on the ⌘ layer — no Sauce, no name-suffix hack — and degrade to Copy, visibly, when Accessibility is missing.
4. **Cycle mode as a state machine under Swift 6.** Problem: "hold ⌘⇧, tap V to step, release to paste" needs the global hotkey disabled after the first key-down and a local monitor reading `flagsChanged` where modifiers release in any order → trick: an explicit `.opening → .toggle | .cycle` machine on the main actor driven by synthesized `NSEvent`s in tests, plus IME marked-text pass-through so ↩ never pastes mid-conversion.
5. **Letting an AI agent verify a GUI app.** Problem: Accessibility trust is bound to the code signature and every rebuild loses it; a glass panel cannot be screenshotted from inside the sandbox → trick: a stable ad-hoc signing identity, a `--ui-testing` mode with an in-memory store, frozen clock, seeded fixtures and stubbed paste, and external capture — every card, modifier state and error state screenshotted without a human.
