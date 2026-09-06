# レビュー記録（2026-09-06）

リリース v0.1.0 の直前に、5 つの観点（並行性/パネル・貼り付け/取り込み・プライバシー/SwiftUI/仕様整合）で
コードレビューを行い、各指摘を 3 名の検証者が**反証を試みる**形で確認した。
2 名以上が「反証できない」と判断したものだけを確定欠陥として採用している（45 件中 39 件が確定、6 件は棄却）。

**確定 39 件のうち 2 件は重複（F14=F1、F15=F2）。実質 37 件、すべて修正済み。**
未対応で残したものはない。

修正コミット: `b3e1396`（モデル・キー処理・コントローラ側）、`0aac213`（SwiftUI 側）、
および `ffb31d8`（F1/F14 の分類順序）とその前後。

| # | 深刻度 | 箇所 | 内容 | 状態 |
|---|---|---|---|---|
| F1 | high | `Nori/Clipboard/ClipboardMonitor.swift:81` | Per-poll Task.detached classification delivers captures out of order | 修正済み |
| F2 | high | `Nori/App/AppCoordinator.swift:53` | Poll-on-open is async, so a just-copied clip lands unselected below the cursor | 修正済み |
| F3 | high | `Nori/Panel/PanelController.swift:61` | ⌘V is posted while the panel is still the key window (orderOut deferred to fade completion) | 修正済み |
| F4 | high | `Nori/Panel/PanelModel.swift:133` | Cycle-mode state machine enters .opening on every open, so the hotkey after a mouse-open cycles and pastes instead of toggling | 修正済み |
| F5 | high | `Nori/Panel/PanelModel.swift:417` | ⌘C in the search field or selectable preview copies the whole clip and closes the panel | 修正済み |
| F6 | high | `Nori/Panel/PanelModel.swift:401` | ⇧⌘1–9 (paste item as plain text) never fires: number row is matched on charactersIgnoringModifiers, which keeps Shift | 修正済み |
| F7 | high | `Nori/Panel/PanelModel.swift:392` | ⌘⌥⇧⌫ wipes the whole history including pinned clips with no confirmation | 修正済み |
| F8 | medium | `Nori/Store/HistoryStore.swift:32` | External-storage blobs stay resident forever once read through the retained ClipItem graph | 修正済み |
| F9 | medium | `Nori/Clipboard/ClipClassifier.swift:165` | WebKit-backed HTML importer runs eagerly inside the detached classification task | 修正済み |
| F10 | medium | `Nori/App/AppCoordinator.swift:175` | ⌘V is posted while the panel is still on screen and key; the stated invariant is not established | 修正済み |
| F11 | medium | `Nori/Settings/SettingsWindowController.swift:70` | Activation policy never returns to .accessory while the menu bar icon is shown (NSApp.windows includes the status item window) | 修正済み |
| F12 | medium | `Nori/Clipboard/ClipClassifier.swift:166` | HTML→string conversion runs eagerly, off the main thread, on every browser copy | 修正済み |
| F13 | medium | `Nori/Clipboard/ClipClassifier.swift:85` | RTF/HTML representations are exempt from every size cap, so multi-MB rich blobs are stored in full | 修正済み |
| F14 | medium | `Nori/Clipboard/ClipboardMonitor.swift:81` | Detached classify tasks can deliver out of order, reordering history and timestamps | F1 と重複 |
| F15 | medium | `Nori/App/AppCoordinator.swift:53` | Panel-open poll is asynchronous, so a just-copied clip pops in under a stale selection | F2 と重複 |
| F16 | medium | `Nori/Model/SecretDetector.swift:24` | Secrets inside clips longer than 20,000 UTF-16 units (or without plain text) are persisted unmasked | 修正済み |
| F17 | medium | `Nori/UI/ExpandedPreview.swift:85` | TextPreview loads full clip blobs and measures 2 MB strings synchronously inside `body` | 修正済み |
| F18 | medium | `Nori/UI/CardContent.swift:282` | File cards hit the filesystem on the main thread every render (uncached stat + NSWorkspace icon) | 修正済み |
| F19 | medium | `Nori/App/AppCoordinator.swift:185` | No-match ↩ only copies the typed text; the empty state and spec promise it pastes | 修正済み |
| F20 | medium | `Nori/Panel/PanelModel.swift:417` | ⌘C is intercepted before the text field, so copying a text selection in the search field or an expanded preview copies the whole clip and closes the panel | 修正済み |
| F21 | medium | `Nori/Settings/PrivacyPane.swift:99` | "Clearing history also clears the system clipboard" is honoured only by the status-menu path, not by the Privacy pane button right beneath it nor by ⌘⇧⌫ | 修正済み |
| F22 | medium | `Nori/Panel/PanelModel.swift:71` | Cycle-mode chip prints the wrong modifiers for ⌃-based hotkeys (e.g. the onboarding-offered ⌃⌥V) and says "to paste" when untrusted | 修正済み |
| F23 | medium | `Nori/App/AppCoordinator.swift:275` | ⌘F is swallowed but does nothing: PanelActions.focusSearch is never wired by the coordinator | 修正済み |
| F24 | low | `Nori/Support/ImageTextRecognizer.swift:8` | Unbounded concurrent Vision requests, each pinning the full-size PNG | 修正済み |
| F25 | low | `Nori/Store/HistoryStore.swift:18` | Lowering maxItems deletes in-context but never saves | 修正済み |
| F26 | low | `Nori/App/StatusItemController.swift:151` | Clear History alert activates Nori and never gives activation back, so the next paste targets Nori | 修正済み |
| F27 | low | `Nori/App/StatusItemController.swift:47` | Right-click menu opens behind the screenSaver-level panel when the panel is already open under the icon | 修正済み |
| F28 | low | `Nori/Clipboard/ClipClassifier.swift:151` | Universal Clipboard images keep the temporary file URL in contents and hash | 修正済み |
| F29 | low | `Nori/Store/HistoryStore.swift:155` | Unpinning at the item limit silently deletes the just-unpinned clip with no undo | 修正済み |
| F30 | low | `Nori/Store/HistoryStore.swift:133` | Undo-restore can create a second row with the same contentHash | 修正済み |
| F31 | low | `Nori/UI/CardMeta.swift:34` | Meta column overflows 128 pt for old pinned rows, truncating the date | 修正済み |
| F32 | low | `Nori/UI/HighlightedText.swift:12` | Search highlights are recomputed by substring only, so fuzzy hits and non-first-line matches show no highlight | 修正済み |
| F33 | low | `Nori/UI/PanelRootView.swift:44` | Clear-history confirmation counts only persisted items, but clearing also wipes the sensitive vault | 修正済み |
| F34 | low | `Nori/UI/PanelRootView.swift:177` | Expand-scroll heuristic assumes a 300 pt card, but file previews can exceed it, leaving the expanded bottom off-screen | 修正済み |
| F35 | low | `Nori/Panel/PanelModel.swift:201` | A degraded ⌘n paste (untrusted) never arms the Accessibility drift banner | 修正済み |
| F36 | low | `Nori/Panel/PanelModel.swift:263` | Hand-rolled pluralisation and String-typed UI copy: "Cleared 1 clips" today, and most panel strings will not reach the en/ja String Catalog | 修正済み |
| F37 | low | `Nori/Panel/HintBarModel.swift:37` | Hint bar prints Paste/Pin/Preview/Delete chips when there is no selectable row or the row is sensitive, where those keys do nothing else or something else | 修正済み |
| F38 | low | `Nori/Panel/PanelModel.swift:412` | ⌃K "unless row 1 is selected" is decided on the raw row index including ghost rows, so with a ghost at the top ⌃K on the first card is swallowed as a no-op | 修正済み |
| F39 | low | `Nori/Panel/PanelModel.swift:131` | Ghost rows that arrive while the panel is open survive the close and are shown again on the next open | 修正済み |

## 棄却した指摘（6 件）

3 名の検証者の過半数が「コードを読む限り再現しない」と判断したもの。参考までに残す。

- `PasteboardSnapshot.swift:56` — スナップショットが全表現をメインスレッドで読む（2 名が反証）
- `PanelPlacement.swift:34` — statusItem 配置が画面クランプを迂回する（2 名が反証）
- `PanelModel.swift:432` — IME 判定の `NSApp.keyWindow` が nil になりうる（3 名が反証）
- `PasteboardSnapshot.swift:56` — 無視ルールの前に全表現を実体化する（3 名が反証）
- `ClipClassifier.swift:81` — 画像サイズ上限が生バイトに掛かり TIFF が早期に ghost 化（3 名が反証）
- `ExpandedPreview.swift:175` — 展開プレビューが画像を切り取る（3 名が反証。その後この箇所は別途調整済み）
