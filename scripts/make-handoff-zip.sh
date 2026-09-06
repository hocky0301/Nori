#!/bin/zsh
# make-handoff-zip.sh [出力先] — 別の開発者・AI に渡す引き継ぎ一式を zip にまとめる。
#
# 入るもの: git 管理下のソースと文書、代表的なスクリーンショット、
#           そして「1ファイルだけ読ませたい」場合用のダイジェスト 2 本。
# 入らないもの: .git / DerivedData / bin / obj / _reference（Maccy 配布物）/ ビルド成果物。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
OUT=${1:-$ROOT/dist/Nori-handoff.zip}
STAGE=$(mktemp -d)/Nori-handoff
mkdir -p "$STAGE" "$(dirname "$OUT")"

# 1. git 管理下のファイルをそのままコピー（管理外＝配布対象外なので _reference 等は自動的に除外される）
git ls-files -z | while IFS= read -r -d '' f; do
  mkdir -p "$STAGE/repo/$(dirname "$f")"
  cp "$f" "$STAGE/repo/$f"
done

# 2. 代表的なスクリーンショットだけ残し、残りは削る（画像はAIには重いだけなので絞る）
KEEP=(panel-light.png panel-dark.png panel-expanded-image.png settings-general.png windows/default.png windows/dark.png)
find "$STAGE/repo/docs/screenshots" -name '*.png' | while read -r p; do
  rel=${p#"$STAGE/repo/docs/screenshots/"}
  [[ " ${KEEP[*]} " == *" $rel "* ]] || rm -f "$p"
done

# 3. ダイジェスト（1 ファイルで読ませたいとき用）
python3 "$ROOT/scripts/make_digest.py" "$ROOT" "$STAGE"

# 4. START_HERE を最上位に
cp "$ROOT/docs/handoff/START_HERE.md" "$STAGE/START_HERE.md"

rm -f "$OUT"
(cd "$(dirname "$STAGE")" && zip -q -r -9 "$OUT" "$(basename "$STAGE")")
rm -rf "$(dirname "$STAGE")"
echo "$OUT ($(du -h "$OUT" | cut -f1))"
