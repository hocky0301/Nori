# Nori

macOS と Windows のクリップボード履歴アプリ。2 実装（Swift / C#）、1 設計。

**作業を始める前に `docs/HANDOFF.md` を読むこと。** 設計の約束・落とし穴・検証方法がすべてそこにある。

## よく使うコマンド

```bash
xcodegen generate                      # ファイルを足したら必ず（.xcodeproj は git 管理外）
scripts/dev-build.sh test              # macOS: ビルド + 193 テスト
scripts/dev-drive.sh launch --seed-demo && scripts/dev-drive.sh cmd open-center
scripts/dev-drive.sh shot /tmp/out.png # パネルを撮って自分で見る
scripts/dev-drive.sh kill
dotnet test windows/Nori.Core.Tests    # Windows: 179 テスト（Mac でも走る）
dotnet build windows/Nori.sln -c Release
```

## 変更してはいけないもの

- `ActionGrammar` の操作文法（↩ ペースト / ⇧ プレーン / ⌥ 開いたまま / ⌘ コピーのみ）。
  **設定で意味を変える項目を足さない。** 詳細は `docs/HANDOFF.md` §4。
- 秘密検出にエントロピー判定を足さない（git SHA や UUID が全部隠れる）。
- 依存を増やさない（macOS: KeyboardShortcuts のみ / Windows: Microsoft.Data.Sqlite のみ）。
- 製品文言に AI ツールのクレジットを入れない。

## 決まりごと

- コミット前に該当プラットフォームのテストを通す。
- ユーザー向け文字列は `String(localized:)` + `Localizable.xcstrings` に ja も追加（Windows は resx 2 本）。
- グラス素材はパネル 1 枚のみ。カードはフラット。
