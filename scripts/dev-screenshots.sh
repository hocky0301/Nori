#!/bin/zsh
# dev-screenshots.sh [outdir] — capture the standard set of panel screenshots from a seeded DEBUG build.
# Requires a Debug build in $NORI_DD (see dev-build.sh). Output defaults to docs/screenshots.
set -e
cd "$(dirname "$0")/.."
OUT=${1:-docs/screenshots}
mkdir -p "$OUT"
D="scripts/dev-drive.sh"

# The panel closes whenever it loses key focus, which other apps can trigger at any time,
# so every shot re-opens the panel (a no-op when it is already open) and re-applies its state.
panel() {                       # panel <name> <cmd>...  → open, apply commands, shoot (retries if the panel got closed)
  local name=$1; shift
  for attempt in 1 2 3; do
    $D cmd open-center; sleep 0.25
    for c in "query:" "filter:all" "mods:none" "$@"; do $D cmd "$c"; done
    sleep 0.45
    if $D shot "$OUT/$name.png" >/dev/null 2>&1; then echo "  $name.png"; return 0; fi
  done
  echo "  $name.png FAILED"; return 1
}

$D launch --seed-demo
panel panel-light          select:2
panel panel-cmd-held       select:2 mods:cmd
panel panel-search         query:swift
panel panel-filter-code    filter:code
panel panel-expanded-image select:4 preview
panel panel-expanded-link  select:6 preview
panel panel-expanded-color select:8 preview
panel panel-ghost          ghost select:2
panel panel-dark           appearance:dark select:2
$D cmd appearance:system; $D cmd close; $D cmd clear
panel panel-empty
$D cmd close; $D cmd settings; sleep 1.2; $D shot "$OUT/settings-general.png" >/dev/null && echo "  settings-general.png"
$D cmd settings:privacy; sleep 0.8;     $D shot "$OUT/settings-privacy.png" >/dev/null && echo "  settings-privacy.png"
$D cmd onboarding; sleep 1.2;           $D shot "$OUT/onboarding-1.png" >/dev/null && echo "  onboarding-1.png"
$D kill
echo "done → $OUT"
