#!/bin/zsh
# build.sh [build|test] — xcodebuild with the noise stripped.
# Env: NORI_ROOT (repo dir), NORI_DD (derived data dir). Defaults: main checkout + shared DerivedData.
ROOT=${NORI_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
DD=${NORI_DD:-$ROOT/DerivedData}
cd "$ROOT" || exit 1
ACTION=${1:-build}
LOG=$DD/last-$ACTION.log
mkdir -p "$DD"
[ -d Nori.xcodeproj ] || xcodegen generate >/dev/null 2>&1
xcodebuild -project Nori.xcodeproj -scheme Nori -configuration Debug \
  -derivedDataPath "$DD" -destination 'platform=macOS' $ACTION > "$LOG" 2>&1
STATUS=$?
grep -E 'error:|warning:.*(/Nori/|/NoriTests/)' "$LOG" | grep -vE 'linkd.autoShortcut|appintentsmetadataprocessor' | sort -u | head -40
grep -E '✘' "$LOG" | head -20
echo "passed: $(grep -c '^✔ Test' "$LOG")  failed: $(grep -c '^✘ Test' "$LOG")"
grep -E '\*\* (BUILD|TEST) (SUCCEEDED|FAILED)' "$LOG"
exit $STATUS
