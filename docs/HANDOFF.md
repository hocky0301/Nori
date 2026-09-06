# Nori 開発引き継ぎ

このリポジトリを別の開発者・別の AI アシスタントが引き継ぐための文書です。
**まずこれを読み、次に `docs/DESIGN.md`（設計の原典）を読んでください。**

最終更新: 2026-09-06 / リリース v0.1.0 時点

---

## 1. これは何か

macOS と Windows のクリップボード履歴アプリ。コピーしたものを「種類ごとに違うカード」で見せ、
キーボードだけで探して貼れる。ネットワークコードは一切なく、履歴はローカルのみ。

- 公開リポジトリ: https://github.com/hocky0301/Nori （MIT）
- 参考にした先行実装: [Maccy](https://github.com/p0deje/Maccy) 2.7.1（MIT）。**フォークではなく、ソースを読んでゼロから書いた別実装**。
  取り込みルール（後述）の判断だけは Maccy の知見をそのまま引き継いでいる。

**2 実装・1 設計。** macOS 版（Swift）と Windows 版（C#）はコードを共有しないが、
判定ロジック（種類判定・秘密検出・検索・操作文法）は 1:1 で移植され、テストも同じケースが両方にある。

| | macOS | Windows |
|---|---|---|
| 言語 | Swift 6（strict concurrency 有効） | C# 13 / .NET 10 |
| UI | SwiftUI + AppKit `NSPanel`（非アクティブ化） | WPF（コードビハインドのみ、XAML なし） |
| 保存 | SwiftData | SQLite（Microsoft.Data.Sqlite） |
| 依存 | KeyboardShortcuts のみ | Microsoft.Data.Sqlite のみ |
| ホットキー | ⇧⌘V | Ctrl+Shift+V |
| 規模 | app 7,722 行 / test 2,902 行（193 ケース） | 合計 9,602 行（テスト 179 ケース） |

※ 行数・テスト数は 2026-09-06 時点のスナップショット。`scripts/dev-build.sh test` と `dotnet test windows/Nori.Core.Tests` を実行すれば現在値が出る。

---

## 2. 5 分で動かす

```bash
# macOS（要 macOS 26 + Xcode 26 + xcodegen）
brew install xcodegen
xcodegen generate            # project.yml から Nori.xcodeproj を生成（.xcodeproj は git 管理外）
scripts/dev-build.sh test    # ビルド＋193 テスト。ノイズを削ってエラーだけ出す
scripts/dev-build.sh build

# Windows 版（macOS/Linux でもビルドとテストは通る。起動だけ Windows が要る）
brew install dotnet
dotnet build windows/Nori.sln -c Release
dotnet test  windows/Nori.Core.Tests
```

**アプリを実際に動かして見る（macOS）**。人間が画面を見なくても検証できるよう、DEBUG ビルドに遠隔操作口がある。

```bash
scripts/dev-drive.sh launch --seed-demo   # メモリ内ストア＋デモデータで起動（本物の履歴に触らない）
scripts/dev-drive.sh cmd open-center      # パネルを画面中央に開く
scripts/dev-drive.sh cmd query:swift      # 検索欄に入力
scripts/dev-drive.sh cmd select:4         # n 番目の行を選ぶ
scripts/dev-drive.sh cmd preview          # 展開プレビュー切替
scripts/dev-drive.sh cmd appearance:dark  # ダークで描画（システム設定は変えない）
scripts/dev-drive.sh shot /tmp/out.png    # そのウィンドウを PNG に撮る → 画像を見て直す
scripts/dev-drive.sh kill
scripts/dev-screenshots.sh docs/screenshots   # README 用の一式を撮り直す
```

コマンド一覧は `Nori/Support/DebugBridge.swift` の `handle(_:)` を見ること。DEBUG ビルドのみ有効。

**Windows 版は開発機（Mac）で起動できない。** 代わりにアプリ自身が全状態を PNG に描き出す。
CI（`.github/workflows/windows.yml`）が `windows-latest` で 11 状態を撮り、artifact `windows-screenshots` に上げる。

```powershell
Nori.exe --state default --screenshot shots/default.png
# --state: default | search:swift | filter:code | cmd | shift | expanded:4 | ghost | empty | dark | settings | onboarding
```

---

## 2.5 やる前に必ず読む「引き返せない操作」

このリポジトリは**公開済み**で、CI が実弾を撃つ。次の操作は取り消せない。

| 操作 | 何が起きるか |
|---|---|
| **`v` で始まる git タグを push**（`git push origin v0.1.1` / `git push --tags`） | `ci.yml` と `windows.yml` の release ジョブが発火し、**公開リポジトリに GitHub Release を即座に公開**する（未署名 zip 2 本 + 自動生成リリースノート付き）。Watcher に通知が飛ぶ。実際に v0.1.0 がこれで公開されている。**リリースを切る意図があるときだけ**打つこと。CI の動作確認をしたいだけなら `test-v1` のような `v*` に一致しない名前を使う。 |
| **`dev-drive.sh` を使わずにアプリを起動**（Xcode の ▶︎、`open Nori.app`、ビルド成果物のダブルクリック） | `--in-memory` が付かないので**本物のクリップボード監視が始まり**、`~/Library/Application Support/Nori` の実データに開発中のゴミが混ざる。さらに初回は本物の Accessibility 許可ダイアログが出る。見た目の確認は必ず `scripts/dev-drive.sh launch --seed-demo` を使う（`--in-memory` が自動で付く）。 |
| `scripts/release.sh` | Release ビルドを作り `dist/` に zip を吐く。公開はしないが、`DerivedData` を汚す。 |
| `scripts/dev-screenshots.sh docs/screenshots` | README 用の画像を**上書き**する。アプリを起動し、マウスカーソルを一時的に画面隅へ動かす。UI を変えた後にだけ実行する。 |
| 設定画面の「ログイン項目」トグル / オンボーディング最終ステップ | `SMAppService` に**本当に登録**される。検証中は触らない。 |

---

## 3. コードの地図

### macOS（`Nori/`）

| ディレクトリ | 役割 |
|---|---|
| `App/` | `main.swift`（エントリ）、`AppCoordinator`（全部を繋ぐ中心）、`StatusItemController`（メニューバー） |
| `Clipboard/` | `ClipboardMonitor`（ポーリング）、`ClipClassifier`（**取り込み判定の心臓**）、`PasteboardSnapshot`、`ClipboardWriter`、`Paster`（⌘V 送出）、`ImageNormalizer` |
| `Model/` | `ClipItem`/`ClipContent`（SwiftData）、`ClipDraft`（値）、`ClipRow`（View 用の値）、`ClipKind`、`KindDetector`、`SecretDetector` |
| `Store/` | `Storage`（コンテナ）、`HistoryStore`（唯一の変更経路）、`SensitiveVault`（秘密をメモリのみ）、`HistorySearch` |
| `Panel/` | `FloatingPanel`/`PanelController`/`PanelPlacement`（AppKit 側）、`PanelModel`（**画面状態とキー処理の全部**）、`ActionGrammar`、`HintBarModel`、`PanelSections`、`PanelFilter` |
| `UI/` | SwiftUI ビュー群。`PanelRootView` が入口 |
| `Settings/` | 設定 4 タブとオンボーディング |
| `Support/` | `NoriSettings`（全設定）、`DebugBridge`（DEBUG 専用）、`ItemOpener`、`ImageTextRecognizer`（OCR） |

**読む順番**: `ClipRow` → `PanelSections` → `ActionGrammar` → `PanelModel` → `AppCoordinator`。
この 5 つが分かればアプリの 8 割が分かる。

### Windows（`windows/`）

- `Nori.Core/` — プラットフォーム非依存。macOS 版からの移植（`PanelModel`, `ClipClassifier`, `KindDetector`, `SecretDetector`, `HistorySearch`, `PanelSections`, `ActionGrammar`, `HintBarModel`, `HistoryStore`, `SensitiveVault`）。Windows 型を一切参照しないので Mac でもテストが走る。
- `Nori.Core.Tests/` — xUnit 179 ケース（Swift 側のテストを移植）。
- `Nori.Windows/` — WPF アプリ本体。`App/App.cs` が合流点、`Panel/PanelController.cs` がパネル、`Native/` が P/Invoke。

---

## 4. 設計上、動かしてはいけない約束

1. **操作文法は 1 つだけ。設定で変えない。**
   `ActionGrammar.resolve(base, bits, capabilities)` が唯一の真実。↩ = ペースト、⇧ = プレーン、
   ⌥ = パネルを閉じない、⌘ = コピーのみ。ビットは重なる。Accessibility 未許可なら paste は全部 copy に降格。
   **ヒントバー・右クリックメニュー・キー処理がすべてこの同じ関数を呼ぶ**ので、画面の表示と実挙動がズレる経路が存在しない。
   ここに「設定で Return の意味を変える」を足すと、この設計が壊れる（Maccy がそうなっていて、それを直したのが Nori）。

2. **秘密はディスクに書かない。**
   API キー・トークン・秘密鍵・Luhn を通るカード番号は `SecretDetector` が検出し、`SensitiveVault`
   （メモリのみ、10 分で消滅、検索対象外、ピン留め不可）へ。エントロピー判定は**入れないこと**
   （git SHA・UUID・base64 が全部隠れて実用にならない。誤検知テストが macOS 16 件・Windows 29 件ある）。

3. **取り込み判定は純関数。**
   `ClipClassifier.classify(snapshot, policy)` は `PasteboardSnapshot`（値）を受けて結果を返すだけ。
   NSPasteboard に触らないのでテストが書ける。ここを AppKit 依存にしないこと。

4. **パネルはフォーカスを奪わない（macOS）。**
   `.nonactivatingPanel` で、開いている間も元のアプリが最前面のまま。だから閉じた直後の ⌘V が元アプリに届く。
   Windows は逆で、入力のためにフォーカスを取り、貼る前に `SetForegroundWindow` で返す。

5. **View は `@Model` を持たない。** SwiftData のオブジェクトは `HistoryStore` の中だけ。
   View には `ClipRow`（Sendable な値）を渡す。画像本体は必要になるまで読まない（一覧はサムネイルのみ）。

---

## 5. 二度と踏まないための落とし穴集

実際に踏んで直したもの。同じ地雷を踏み直さないこと。

### macOS
- **`@main` を `NSApplicationDelegate` に付けても delegate は登録されない。** storyboard が無いと無音で何も起きない。`main.swift` で自分で `app.delegate = …` する。
- **SwiftData: `init` の中でリレーションに代入すると `EXC_BREAKPOINT`。** `context.insert` の後に子を insert して親を指す。
- **SwiftData: 同一プロセスに `ModelContainer` を 2 つ作ると insert で落ちる。** テストはアプリをホストに走るので、テストも `Storage.shared.context` を共有し `@Suite(.serialized)` にする。
- **`charactersIgnoringModifiers` は Shift を無視しない。** ⇧⌘1 は `"!"` を返す。数字キーは **keyCode** で判定する（`PanelModel` の 1…9 対応表）。
- **分類を `Task.detached` に投げると順番が入れ替わる。** 重いスクショの後の軽いテキストが先に着き、履歴の順序と時刻が壊れる。`pendingClassification` チェーンで直列化し、`capturedAt` を `ingest` まで通す。
- **`resignKey` で閉じる設計上、他アプリが自分をキーに戻すとパネルが勝手に閉じる。** 挙動としては正しい。スクショを撮るときは撮る直前に開き直す（`scripts/dev-screenshots.sh` がリトライ込みでやっている）。
- **非対話シェルから直接 exec したアプリは WindowServer に繋がらない。** `open -n App.app --args …` で LaunchServices 経由に。
- **`Regex` は Sendable でない** → `nonisolated(unsafe) static let`。**`NSEvent` も Sendable でない** → `MainActor.assumeIsolated` の戻り値に使わない。

### Windows
- **単一ファイル発行でしか出ないバグがある。** `Assembly.Location` は空文字を返す（IL3000）。`Environment.ProcessPath` を使う。
  **`dotnet build` では出ない。** ローカル再現は `dotnet publish -p:PublishSingleFile=true`。
- **`UseWPF` と `UseWindowsForms` を両方有効にすると `Application` / `MessageBox` が曖昧になる。** `System.Windows.` で完全修飾する（csproj で `Using Remove` 済み）。
- **自己完結の exe は 176MB。** `EnableCompressionInSingleFile=true` で 74MB。

---

## 6. 品質の現状

- テスト: macOS **193**、Windows **179**。両方グリーン。CI は push ごとに両方走る。
- 多角レビュー（5 観点 × 3 名の敵対検証）を実施済み。確認された欠陥 **37 件**は全部修正済み
  （報告 39 件のうち F14・F15 が F1・F2 と重複）。**全 39 件の一覧と対応状況は `docs/REVIEW_LOG.md`**。
  修正はコミット `b3e1396`（core 側）/ `0aac213`（UI 側）とその前後にある。
- 未検証の領域（正直に）:
  - **Windows アプリの実機での手触り**。CI のスクリーンショットとロジックテストまでしか見ていない。
    トレイ・ホットキー・クリップボード監視・貼り付けの実挙動は**人間の確認が必要**。
  - macOS のメニュー操作（⋯ メニュー・右クリックメニュー）をクリックで開いた時に、
    非アクティブ化パネルがキーを失って閉じないか。
  - 貼り付けの成否は Accessibility 許可が要るため、開発ビルドでは常に「コピーに降格」した状態しか見ていない。

---

## 7. 次にやるなら（優先度順）

1. **署名と公証。** 今は両方とも未署名。Mac は初回に `xattr -d com.apple.quarantine`、Windows は SmartScreen 警告が出る。
   Apple Developer ID と Windows のコード署名証明書があれば消せる。ユーザー体験として一番大きい残課題。
2. **Windows 実機での通し確認。** 上記「未検証」を人間が一度触る。
3. **Windows のサイクルモード。** macOS にはある「ショートカット押しっぱなしで送る」が Windows は未実装
   （`HintBarModel` の `CycleMode` は false 固定）。`WM_HOTKEY` の連打 + `GetAsyncKeyState` で実装できるはず。
4. **App Sandbox（macOS）。** 現在オフ。有効化するとファイル URL の復元と Accessibility の扱いを再設計する必要がある。
5. **Homebrew cask / winget。** 署名が済んでから。

---

## 8. 作業のときの約束事

- **コミット前に必ず `scripts/dev-build.sh test`（と Windows を触ったなら `dotnet test`）を通す。**
- ファイルを足したら `xcodegen generate`。`.xcodeproj` は git 管理外で、`project.yml` が正。
- ユーザー向け文字列は `String(localized:)` を通し、`Nori/Resources/Localizable.xcstrings` に **ja も**足す
  （Windows は `Resources/Strings.resx` と `Strings.ja.resx`）。日本語は横幅が伸びるのでヒントバーは特に短く。
- **AI ツールのクレジットを製品側の文言に入れない**（README・About・オンボーディング・リリースノート・記事）。
  リポジトリ所有者の名前で公開しているため。
- 依存を増やさない。macOS は KeyboardShortcuts のみ、Windows は Microsoft.Data.Sqlite のみ。
- グラス素材はパネル 1 枚だけ。カード・チップ・キーキャップはその上のフラットな面（重ねると 500 行のスクロールが落ちる）。

---

## 9. 資料の場所

| ファイル | 中身 |
|---|---|
| `docs/DESIGN.md` | 設計の原典。パネル寸法・カード構造・キー割り当て・取り込み規則の根拠。**実装との差分は冒頭の表** |
| `docs/WINDOWS_DESIGN.md` | Windows 版の設計指示書。差分は冒頭 |
| `docs/REVIEW_LOG.md` | リリース前レビューで確定した 39 件の一覧と対応状況（実質 37 件、全部修正済み） |
| `docs/zenn/nori-clipboard-manager.md` | 技術記事の下書き（`published: false`、投稿は所有者が行う） |
| `windows/README.md` | Windows 版のビルドと検証手順 |
| `README.md` | 利用者向け |
| `scripts/make-handoff-zip.sh` | 引き継ぎ一式（`dist/Nori-handoff.zip`）を作り直す。文書やコードを更新したら実行する |
| `_reference/` | Maccy 2.7.1 の配布物（**git 管理外**なので clone しても存在しない）。`docs/DESIGN.md` は `Maccy/...` のパスを根拠として引用するので、裏を取りたいときは https://github.com/p0deje/Maccy の tag 2.7.1 を取得してここに展開する。無くても実装作業に支障はない |

---

## 10. 引き継ぐ相手へ

このプロジェクトで一番価値があるのは、コードそのものより **§4（動かしてはいけない約束）と §5（落とし穴集）** です。
特に「操作文法を 1 つに固定する」は Nori の存在理由そのもので、ここに設定項目を足す変更が来たら、
それは機能追加ではなく設計の後退です。まずこの判断の背景（`docs/DESIGN.md` §1）を読んでから議論してください。
