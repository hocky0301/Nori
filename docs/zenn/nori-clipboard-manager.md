---
title: "macOS 26 でクリップボード履歴アプリをゼロから作って踏んだ落とし穴 10 個 ── NSPasteboard・非アクティブ化パネル・SwiftData・Swift 6"
emoji: "🧷"
type: "tech"
topics: ["macos", "swift", "swiftui", "swiftdata", "wpf"]
published: false
---

Maccy（macOS 定番のクリップボード履歴アプリ、MIT）のソースを全部読んでから、**同じ問題を解く別のアプリ「Nori（糊）」を Swift 6 / SwiftUI / SwiftData でゼロから書きました**。
この記事は「作ってみた」ではなく、その過程で **実際に踏んで、実際に直した落とし穴 10 個** と、Maccy と違う判断をした 3 箇所の記録です。
macOS でクリップボード系ツールを書く人、Swift 6 の strict concurrency で AppKit を触る人、GUI アプリの動作確認をスクリプトから自動で回したい人に向けています。

- リポジトリ: https://github.com/hocky0301/Nori （MIT）
- 参考にした本家: https://github.com/p0deje/Maccy

## 環境

| 項目 | バージョン |
|---|---|
| macOS | 26.5 (25F71) |
| Xcode | 26.6 (17F113) / Swift 6.3.3 |
| デプロイターゲット | macOS 26.0 |
| 依存パッケージ | sindresorhus/KeyboardShortcuts 2.4.0 のみ |
| プロジェクト生成 | xcodegen 2.45.4 |
| 読んだ本家 | Maccy 2.7.1（Swift 117 ファイル / 9,637 行） |

## 結論から

1. **NSPasteboard に変更通知はない**。全員 `changeCount` をポーリングしている。Nori は 200 ms。
2. クリップボードマネージャーの難所は UI ではなく **「フォーカスを奪わずにキーボードを受け取り、閉じた瞬間に元アプリへ ⌘V を送る」** の一点。
3. Swift 6 の strict concurrency は AppKit 相手だと **「型が Sendable じゃない」系のエラーを 3 種類** 踏む。全部 1 行で直る。
4. SwiftData は **insert の前にリレーションを触ると落ちる**、**同一プロセスに ModelContainer を 2 つ作ると落ちる**。どちらもメッセージなしの `EXC_BREAKPOINT`。
5. GUI アプリの動作確認を自動化するなら、**アプリ側に DEBUG 専用の遠隔操作口を作って、外から `screencapture -l` で撮る** のが一番安定した。

## Maccy を読んでわかった「クリップボード履歴アプリの本体」

Maccy 2.7.1 は 9,637 行ありますが、アプリの本体は 3 ファイルに集約されています。

- `Clipboard.swift` ── ポーリングと取り込みルール。`org.nspasteboard.ConcealedType`（パスワードマネージャーが付ける「保存するな」印）の扱い、BBEdit や Edge が 1 コピーで 2 アイテム置く問題、Word のブックマーク型を消さないと Word が自分へのリンクをペーストしてしまう問題（Maccy #613/#770）、`dyn.` で始まる動的型の除外。
- `FloatingPanel.swift` ── `NSPanel` を `.nonactivatingPanel` で作り、`level = .screenSaver`（Chrome のオートフィルが 999 なのでその上）、キーを失ったら閉じる。
- `Popup.swift` ── ホットキーを押しっぱなしで「もう一回押すと次の項目、離すとペースト」というサイクルモードの状態機械。

つまり **エッジケースの塊は取り込みルールで、UI は薄い**。だから「UI を綺麗にした別アプリ」を作るなら、取り込みルールは Maccy の判断を全部引き継ぎ、UI と操作体系だけ設計し直すのが正解だと判断しました。Nori の `ClipClassifier.swift` は Maccy の `Clipboard.swift` の判断をテスト付きで純関数に写したものです。

## 踏んだ落とし穴 10 個

### 1. `@main` を NSApplicationDelegate に付けても delegate は入らない

**症状**: アプリは起動する。プロセスは生きている。でもステータスバーにアイコンが出ず、ログも一切出ない。

**切り分け**: `sample` で main スレッドを見ると `NSApplicationMain → -[NSApplication run]` でイベント待ちをしているだけ。`applicationDidFinishLaunching` が呼ばれていない。

```
845 static NoriApp.$main()  (in Nori.debug.dylib)
  845 static NSApplicationDelegate.main()  (in Nori.debug.dylib)
    845 NSApplicationMain  (in AppKit) + 880
      845 -[NSApplication run]  (in AppKit) + 368
```

**原因**: `@main final class NoriApp: NSObject, NSApplicationDelegate` は `NSApplicationMain()` を呼ぶだけで、**delegate のインスタンスを作って登録してはくれない**。Xcode のテンプレートで動くのは Main.storyboard が delegate を生成しているからで、storyboard のないメニューバーアプリでは無音で何も起きません。

**直し方**: `main.swift` を自分で書く。

```swift
import AppKit

let app = NSApplication.shared
let delegate = NoriApp()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

Maccy が SwiftUI の `App` に「常に非表示の `MenuBarExtra`」を置いて回避しているのはこのためです（`MaccyApp.swift` のコメントに "It's impossible to create sceneless application" とあります）。

### 2. SwiftData: init でリレーションを代入すると `EXC_BREAKPOINT`

**症状**: `context.insert(item)` で `Trace/BPT trap: 5`。メッセージなし。クラッシュレポートの先頭フレームは SwiftData 内部。

**原因**: `@Model` クラスの `init` の中で `contents = draft.contents.map { ClipContent(...) }` と to-many リレーションに配列を入れていた。SwiftData はモデルがコンテキストに入る前のリレーション操作でトラップする。

**直し方**: init ではリレーションを空にしておき、insert してから子を insert して親を指す。

```swift
let item = ClipItem(draft: draft, now: now)   // contents = []
context.insert(item)
for content in draft.contents {
    let row = ClipContent(type: content.type, data: content.data)
    context.insert(row)
    row.item = item
}
```

### 3. SwiftData: 同一プロセスに ModelContainer を 2 つ作ると insert で落ちる

**症状**: 2 と同じ `EXC_BREAKPOINT` が、直したはずなのにテストでだけ再現する。アプリ本体では起きない。

**切り分け**: テストはアプリをホストにして走る。アプリ起動時に `Storage.shared` が in-memory の `ModelContainer` を作り、テストが各ケースでさらに `ModelContainer` を作っていた。ケースごとに新しいコンテナ、計 2 つ以上。

**直し方**: テストもアプリのコンテナを共有し、各ケースの冒頭で全削除する。`@Suite(.serialized)` にする。

```swift
private func makeStore() throws -> HistoryStore {
    let store = HistoryStore(context: Storage.shared.context)
    store.load()
    store.clear(includingPinned: true)
    return store
}
```

同じスキーマのコンテナを複数持てないのは仕様なのか不具合なのかは **未確認** です（公式ドキュメントに記述を見つけられませんでした）。

### 4. Swift 6 strict concurrency で踏んだ 3 種類のエラー

全部そのまま貼ります。

```
error: static property 'hexColor' is not concurrency-safe because non-'Sendable' type 'Regex<Substring>' may have shared mutable state
```
`Regex` は Sendable ではない。正規表現を `static let` に置けない。→ `nonisolated(unsafe) private static let`（実際には不変なので安全）。

```
error: conformance of 'NSEvent' to 'Sendable' is unavailable
```
`MainActor.assumeIsolated { ... }` の戻り値に `NSEvent?` を使っていた。`assumeIsolated` の戻り値は Sendable 必須。→ クロージャ内では Bool（処理したか）だけ返し、イベントは外で返す。

```
error: reference to var 'kAXTrustedCheckOptionPrompt' is not concurrency-safe because it involves shared mutable state
```
Accessibility 許可ダイアログを出すためのグローバル定数が `var` 扱い。→ 文字列リテラル `"AXTrustedCheckOptionPrompt"` を直接キーに使う。

どれも 1 行で直りますが、**エラー文が「なぜダメか」を言ってくれないので、初見だと数分ずつ止まります**。

### 5. パスワードマネージャーの「保存するな」印は、アイテムではなくペーストボードに付いている

`NSPasteboard.general.types`（ペーストボード全体の型一覧）と `pasteboardItems[i].types`（各アイテムの型一覧）は一致しません。1Password などが付ける `org.nspasteboard.ConcealedType` は前者にだけ現れることがある（Maccy #241）。

Nori では取り込み判定の最初に **ペーストボード全体の型集合（union）** を見て、`ConcealedType` があれば内容を一切読まずに「1Password のコピーは保存しませんでした」というゴースト行だけを残します。テストでは「アイテムには無いが declaredTypes にはある」というスナップショットを作って固定しています。

```swift
@Test func concealedLeavesAGhostEvenWhenOnlyDeclared() {
    let snap = snapshot([[text("hunter2")]],
                        declared: [PasteboardType.utf8PlainText, PasteboardType.concealed],
                        appName: "1Password")
    #expect(ClipClassifier.classify(snap) == .ghost(.concealed(appName: "1Password")))
}
```

### 6. 複数ファイルのコピーは「同じ型のアイテムが複数」なので、型で重複排除すると 2 個目が消える

Finder で 2 ファイルをコピーすると、ペーストボードには `public.file-url` を持つアイテムが 2 つ載ります。「1 コピーに複数アイテム（BBEdit / Edge 対策）はマージして、型の重複は最初の 1 つだけ採用」というルールをそのまま適用すると、2 つ目のファイル URL が捨てられました。テストが落ちて気付いた例です。

```
✘ Test files() … Expectation failed: (draft.fileURLs.map(\.lastPathComponent) → ["My File.txt"]) == ["My File.txt", "other.pdf"]
```

→ `public.file-url` だけは重複を許す。書き戻す側も Maccy と同じく、ファイル URL は `writeObjects([NSPasteboardItem])` で 1 URL = 1 アイテムにしないと複数ファイルのペーストが Finder で動きません。

### 7. 非アクティブ化パネルは「自分が触っていないのに」キーを失うことがある

パネルは `.nonactivatingPanel` なので、開いている間もユーザーが使っていたアプリがアクティブなままです。Maccy と同じく `resignKey()` で閉じる実装にしたところ、**何も操作していないのに開いて 6 秒後に閉じる** 現象が出ました。

```
19:24:15.149 opened panel at 620.0,372.7 key=true
19:24:21.139 resignKey; new key=nil active=false
19:24:21.139 closing panel (resignKey)
```

再現条件を詰めると、前面にいた Electron 製アプリが画面更新のたびに自分のウィンドウをキーに戻していました。人間が使う分には「他アプリをクリックしたら閉じる」で正しい挙動なので、Nori も **閉じる契機は resignKey のまま** にし、代わりに「開いた直後の数秒は再びキーを取り直す」ような小細工はしていません。ただし **自動テストでスクリーンショットを撮るときは、撮る直前にもう一度 open を送る** 運用にしました。これは実装の問題ではなく検証手順の問題として解決しています。

### 8. 非対話のシェルから直接 `exec` したアプリは WindowServer に繋がらない

自動化スクリプトから `./Nori.app/Contents/MacOS/Nori &` で起動すると、プロセスは生きるのにウィンドウが一切作れません（`CGWindowListCopyWindowInfo` にも出ない）。`open -n Nori.app --args …` で LaunchServices 経由にすると普通に動きます。GUI の検証を自動化するときに最初に踏む壁です。

### 9. 分類を `Task.detached` に投げると、履歴の順番が入れ替わる

取り込みの分類（画像の PNG 変換・サムネイル生成・SHA-256）はメインスレッドでやりたくないので、ポーリングで変化を検知するたびに `Task.detached` に投げていました。これは **順序を保証しない** ので、スクリーンショット（数百 ms かかる）を撮った直後に短いテキストをコピーすると、テキストの分類が先に終わって先に履歴に入り、あとから画像が「最新」として上に積まれます。↩ で貼られるのは意図と違う項目になる。

自分では気付かず、コードレビューで指摘されました。直し方は「前のタスクを await してから自分の分類を始める」チェーンにして、履歴に入れるときはコピー時刻でソート位置を決めること。

```swift
let previous = pendingClassification
pendingClassification = Task(priority: .userInitiated) { [weak self] in
    await previous?.value
    let outcome = await Task.detached { ClipClassifier.classify(snapshot, policy: policy) }.value
    self?.deliver(outcome, capturedAt: snapshot.capturedAt)
}
```

### 10. `charactersIgnoringModifiers` は Shift を無視しない

「⇧⌘1 でプレーンテキストとして貼る」を、`event.charactersIgnoringModifiers` が `"1"` を返す前提で `Int(char)` にかけていました。ところがこのプロパティが無視するのは ⌘ と ⌥ だけで、**Shift は反映されます**。US 配列で ⇧⌘1 を押すと `"!"` が返り、数字として解釈されず、ショートカットが無音で効かない。JIS 配列では別の記号になるので、さらに混乱します。

数字キーは文字ではなく **キーコード**（kVK_ANSI_1…9 = 18, 19, 20, 21, 23, 22, 26, 28, 25。テンキーは 83〜92）で判定するのが正解でした。これもコードレビューで見つかったもので、テストは「⇧付きの数字イベント」を合成して固定しています。

## Maccy と違う判断をした 3 箇所

### 操作体系を「文法」1 つに固定した

Maccy は「Return でコピーかペーストか」「書式を落とすか」を設定で切り替えられ、修飾キーとの組み合わせで 12 通りの分岐があります（`HistoryItemAction.swift`）。結果として「今 Return を押すと何が起きるか」が設定に依存します。

Nori は **設定で変えられない文法を 1 つ** にしました。

- ↩ はペースト
- ⇧ を足すとプレーンテキスト、⌥ を足すとパネルを閉じない、⌘ を足すとコピーだけ
- ビットは重ねられる（⇧⌥↩ = プレーンでペーストして閉じない）
- Accessibility 未許可なら「ペースト」は全部「コピー」に格下げ

```swift
static func resolve(_ base: Base, _ bits: Bits, _ caps: Capabilities) -> Action {
    let plain = bits.contains(.plain)
    let keepOpen = bits.contains(.keepOpen)
    let copyOnly: Bool = if case .number = base { false } else { bits.contains(.copyOnly) }
    if copyOnly || !caps.accessibilityTrusted {
        return .copy(plain: plain, keepOpen: keepOpen)
    }
    return .paste(plain: plain, keepOpen: keepOpen)
}
```

この関数を **キー処理とヒントバーの両方が呼ぶ** ので、画面下に出ている「⇧↩ Plain」「⌘↩ Copy」の表示と実際の動作が食い違う経路が存在しません。8 通りの修飾キー × 3 種類の起点 × 許可あり/なし の真理値表がそのままテストです。

### シークレットは SQLite に書かない

API キー・トークン・秘密鍵・カード番号（Luhn 検証付き）は正規表現で検出し、**マスクした状態でメモリだけに 10 分間** 置きます。検索対象にならず、ピン留めもできず、ペーストはできる。エントロピー系のヒューリスティックは入れていません（git の SHA や UUID が全部隠れて実用にならないため）。誤検知テストには SHA-1/SHA-256/UUID/base64/Luhn を通らない 16 桁などを入れています。

### 画像は PNG だけ保存し、一覧用サムネイルを行に埋め込む

スクリーンショットを 1 枚コピーすると、ペーストボードには TIFF（数十 MB）と PNG（数百 KB）の両方が載ります。Nori は PNG があればそれだけ、TIFF しか無ければ `CGImageSource → CGImageDestination` で PNG に変換して保存します。一覧に出す 224px のサムネイルは `CGImageSourceCreateThumbnailAtIndex` で作って `ClipItem` に直接持たせるので、**一覧のスクロール中にフル画像をデコードすることはありません**。本体の PNG は SwiftData の `.externalStorage` です。

## GUI の動作確認をどう自動化したか

毎回手で画面を確認しなくて済むように、検証手順そのものをアプリに組み込みました。

1. **DEBUG ビルド限定の遠隔操作口**: `DistributedNotificationCenter` で `open-center` / `query:swift` / `filter:link` / `ghost` / `clear` などの命令を受ける `DebugBridge`。並列に複数インスタンスを動かすため `--debug-channel=名前` で購読名を分ける。
2. **in-memory ストア + デモデータ**: `--in-memory --seed-demo` で起動すると本物の履歴に触らず、リンク/コード/色/画像/ファイル/シークレットが揃った状態になる。
3. **外からスクリーンショット**: `CGWindowListCopyWindowInfo` で自分の PID のウィンドウ番号を引き、`screencapture -x -l <window>` で撮る。Liquid Glass のパネルは半透明なので、アプリ内でビューを描画しても背景がなくて評価できません。
4. 撮った PNG を見て、余白・切れ・コントラストを直す。

```bash
scripts/dev-drive.sh launch --seed-demo
scripts/dev-drive.sh cmd open-center
scripts/dev-drive.sh shot panel.png
```

このループが回るようになってから、UI 実装は 3 つのワークツリーで並列に進めました（パネル UI / 設定画面とオンボーディング / テスト）。最終的に macOS 版は Swift 7722 行 + テスト 2902 行（193 ケース）、Windows 版は C# 9602 行（テスト 179 ケース）になっています。

## Windows 版も作った ── 同じ設計、違う機構

「Mac だけだと片手落ちだよね」ということで、Windows 版（C# / .NET 10 / WPF）も作りました。Swift のコードは 1 行も動かないので別実装ですが、**判定ロジックは 1:1 で移植**しています（`Nori.Core`。テストも同じケースを xUnit に移して 179 件）。

移植して初めて気付いた、macOS と Windows の違いが 3 つあります。

| | macOS | Windows |
|---|---|---|
| クリップボードの変化 | 通知が無い。`changeCount` を 200ms ポーリング | `AddClipboardFormatListener` で `WM_CLIPBOARDUPDATE` が飛んでくる。**ポーリング不要** |
| 「保存するな」印 | `org.nspasteboard.ConcealedType`（有志の規約） | `ExcludeClipboardContentFromMonitorProcessing` / `CanIncludeInClipboardHistory`（OS 公式） |
| パネルのフォーカス | 非アクティブ化パネルで**フォーカスを奪わない**。だから ⌘V がそのまま元アプリに届く | フォーカスを奪わないと文字入力ができない。だから元の HWND を覚えておいて、閉じてから `SetForegroundWindow` → `SendInput` で Ctrl+V |

3 つ目が一番効きます。macOS は「奪わない」ことに苦労し、Windows は「返す」ことに苦労する。同じ機能なのに難所が正反対でした。

### CI でしか動かせないアプリを、どう確認するか

開発機は Mac なので、WPF アプリはビルドはできても**起動できません**（`EnableWindowsTargeting` でコンパイルだけ通る）。そこでアプリ自身にスクリーンショットモードを持たせ、GitHub Actions の `windows-latest` で全状態を撮って artifact に上げるようにしました。

```powershell
Nori.exe --state default --screenshot shots/default.png
```

`--state` は `default / search:swift / filter:code / cmd / shift / expanded:4 / ghost / empty / dark / settings / onboarding` の 11 種類。時計は固定なので「2分前」の表示もブレず、UI が変わったときだけ画像が変わります。

この仕組みのおかげで、**単一ファイル発行でしか出ないバグ**も CI が捕まえました。

```
error IL3000: 'System.Reflection.Assembly.Location.get' always returns an empty string
for assemblies embedded in a single-file app.
```

「Windows 起動時に実行」をレジストリに書くとき、exe のパスを `Assembly.Location` で取ろうとしていた箇所です。単一ファイルに固めると常に空文字を返すので、`Environment.ProcessPath` を使うのが正解でした。ローカルの `dotnet build` は通り、`dotnet publish -p:PublishSingleFile=true` で初めて落ちます。

なお自己完結（.NET ランタイム同梱）の単一 exe は **176MB** ありました。`EnableCompressionInSingleFile=true` を付けて **74MB**。ユーザーに「まず .NET を入れてください」と言わずに済む代わりの重さです。

## できていないこと

- Developer ID がないので配布ビルドは ad-hoc 署名です。初回だけ `xattr -d com.apple.quarantine` が要ります。
- App Sandbox は未対応。
- 画像 OCR（スクリーンショットの文字検索）は実装済みですが既定でオフ（Vision の結果が非決定的でテストしづらいため）。
- Chrome Remote Desktop / NetBeans など、合成した ⌘V を無視するアプリへの対策（Maccy がやっているアクティベート→隠す小技）は入れていません。
- UI は英語と日本語（String Catalog）。他言語は未対応。
- Windows 版はサイクルモード（ショートカット押しっぱなしで送る）が未実装。

## まとめ

- クリップボード履歴アプリの本体は取り込みルールと「フォーカスを奪わない ⌘V」で、UI は薄い。だから UI を作り直すなら Maccy の判断は全部引き継いでよい。
- SwiftData の `EXC_BREAKPOINT` はメッセージが無い。「insert 前のリレーション」「コンテナ 2 個」の 2 つを先に疑う。
- Swift 6 の Sendable エラーは `Regex` / `NSEvent` / Carbon のグローバル定数 で出る。直し方は 1 行。
- GUI の検証口（遠隔操作 + 外部スクリーンショット）を先に作ると、その後の UI 作業が全部楽になる。
- 同じアプリを macOS と Windows で作ると、難所がきれいに反転する。macOS はフォーカスを「奪わない」ため、Windows は「返す」ために苦労する。

コードはすべて https://github.com/hocky0301/Nori にあります。Maccy の作者 Alexey Rodionov 氏に感謝を。
