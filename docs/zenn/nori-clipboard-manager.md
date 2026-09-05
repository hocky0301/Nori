---
title: "macOS 26 でクリップボード履歴アプリをゼロから作って踏んだ落とし穴 8 つ ── NSPasteboard・非アクティブ化パネル・SwiftData・Swift 6"
emoji: "🧷"
type: "tech"
topics: ["macos", "swift", "swiftui", "swiftdata", "claudecode"]
published: false
---

Maccy（macOS 定番のクリップボード履歴アプリ、MIT）のソースを全部読んでから、**同じ問題を解く別のアプリ「Nori（糊）」を Swift 6 / SwiftUI / SwiftData でゼロから書きました**。実装はほぼ全部 Claude Code に任せています。
この記事は「作ってみた」ではなく、その過程で **実際に踏んで、実際に直した落とし穴 8 つ** と、Maccy と違う判断をした 3 箇所の記録です。
macOS でクリップボード系ツールを書く人、Swift 6 の strict concurrency で AppKit を触る人、AI エージェントに GUI アプリを作らせて検証まで回したい人に向けています。

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
| 実装 | Claude Code（Claude Fable 5.1） |

## 結論から

1. **NSPasteboard に変更通知はない**。全員 `changeCount` をポーリングしている。Nori は 200 ms。
2. クリップボードマネージャーの難所は UI ではなく **「フォーカスを奪わずにキーボードを受け取り、閉じた瞬間に元アプリへ ⌘V を送る」** の一点。
3. Swift 6 の strict concurrency は AppKit 相手だと **「型が Sendable じゃない」系のエラーを 3 種類** 踏む。全部 1 行で直る。
4. SwiftData は **insert の前にリレーションを触ると落ちる**、**同一プロセスに ModelContainer を 2 つ作ると落ちる**。どちらもメッセージなしの `EXC_BREAKPOINT`。
5. AI に GUI アプリを検証させるなら、**アプリ側に DEBUG 専用の遠隔操作口を作って、外から `screencapture -l` で撮る** のが一番安定した。

## Maccy を読んでわかった「クリップボード履歴アプリの本体」

Maccy 2.7.1 は 9,637 行ありますが、アプリの本体は 3 ファイルに集約されています。

- `Clipboard.swift` ── ポーリングと取り込みルール。`org.nspasteboard.ConcealedType`（パスワードマネージャーが付ける「保存するな」印）の扱い、BBEdit や Edge が 1 コピーで 2 アイテム置く問題、Word のブックマーク型を消さないと Word が自分へのリンクをペーストしてしまう問題（Maccy #613/#770）、`dyn.` で始まる動的型の除外。
- `FloatingPanel.swift` ── `NSPanel` を `.nonactivatingPanel` で作り、`level = .screenSaver`（Chrome のオートフィルが 999 なのでその上）、キーを失ったら閉じる。
- `Popup.swift` ── ホットキーを押しっぱなしで「もう一回押すと次の項目、離すとペースト」というサイクルモードの状態機械。

つまり **エッジケースの塊は取り込みルールで、UI は薄い**。だから「UI を綺麗にした別アプリ」を作るなら、取り込みルールは Maccy の判断を全部引き継ぎ、UI と操作体系だけ設計し直すのが正解だと判断しました。Nori の `ClipClassifier.swift` は Maccy の `Clipboard.swift` の判断をテスト付きで純関数に写したものです。

## 踏んだ落とし穴 8 つ

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

再現条件を詰めると、前面にいた Electron 製アプリ（この時は Claude デスクトップアプリ）が画面更新のたびに自分のウィンドウをキーに戻していました。人間が使う分には「他アプリをクリックしたら閉じる」で正しい挙動なので、Nori も **閉じる契機は resignKey のまま** にし、代わりに「開いた直後の数秒は再びキーを取り直す」ような小細工はしていません。ただし **自動テストでスクリーンショットを撮るときは、撮る直前にもう一度 open を送る** 運用にしました。これは実装の問題ではなく検証手順の問題として解決しています。

### 8. AI エージェントのシェルから直接 `exec` したアプリは WindowServer に繋がらない

Claude Code の Bash から `./Nori.app/Contents/MacOS/Nori &` で起動すると、プロセスは生きるのにウィンドウが一切作れません（`CGWindowListCopyWindowInfo` にも出ない）。`open -n Nori.app --args …` で LaunchServices 経由にすると普通に動きます。エージェントが GUI を検証するときに最初に踏む壁です。

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

## AI にどうやって GUI を検証させたか

人間が画面を見ないので、検証手順そのものをアプリに組み込みました。

1. **DEBUG ビルド限定の遠隔操作口**: `DistributedNotificationCenter` で `open-center` / `query:swift` / `filter:link` / `ghost` / `clear` などの命令を受ける `DebugBridge`。並列に複数インスタンスを動かすため `--debug-channel=名前` で購読名を分ける。
2. **in-memory ストア + デモデータ**: `--in-memory --seed-demo` で起動すると本物の履歴に触らず、リンク/コード/色/画像/ファイル/シークレットが揃った状態になる。
3. **外からスクリーンショット**: `CGWindowListCopyWindowInfo` で自分の PID のウィンドウ番号を引き、`screencapture -x -l <window>` で撮る。Liquid Glass のパネルは半透明なので、アプリ内でビューを描画しても背景がなくて評価できません。
4. エージェントは撮った PNG を読んで、余白・切れ・コントラストを自分で直す。

```bash
scripts/dev-drive.sh launch --seed-demo
scripts/dev-drive.sh cmd open-center
scripts/dev-drive.sh shot panel.png
```

このループが回るようになってから、UI 実装は 3 つのワークツリーで並列に進めました（パネル UI / 設定画面とオンボーディング / テスト）。【要確認: 最終的なテスト数・LOC・スクリーンショット】

## できていないこと

- Developer ID がないので配布ビルドは ad-hoc 署名です。初回だけ `xattr -d com.apple.quarantine` が要ります。
- App Sandbox は未対応。
- 画像 OCR（スクリーンショットの文字検索）は実装済みですが既定でオフ（Vision の結果が非決定的でテストしづらいため）。
- Chrome Remote Desktop / NetBeans など、合成した ⌘V を無視するアプリへの対策（Maccy がやっているアクティベート→隠す小技）は入れていません。

## まとめ

- クリップボード履歴アプリの本体は取り込みルールと「フォーカスを奪わない ⌘V」で、UI は薄い。だから UI を作り直すなら Maccy の判断は全部引き継いでよい。
- SwiftData の `EXC_BREAKPOINT` はメッセージが無い。「insert 前のリレーション」「コンテナ 2 個」の 2 つを先に疑う。
- Swift 6 の Sendable エラーは `Regex` / `NSEvent` / Carbon のグローバル定数 で出る。直し方は 1 行。
- AI に GUI を作らせるなら、検証口（遠隔操作 + 外部スクリーンショット）を先に作るとその後が全部楽になる。

コードはすべて https://github.com/hocky0301/Nori にあります。Maccy の作者 Alexey Rodionov 氏に感謝を。
