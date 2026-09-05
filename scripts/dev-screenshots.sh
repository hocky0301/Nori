#!/bin/zsh
# dev-screenshots.sh [outdir] — capture the standard set of panel screenshots from a seeded DEBUG build.
# Requires a Debug build in $NORI_DD (see dev-build.sh). Output defaults to docs/screenshots.
set -e
cd "$(dirname "$0")/.."
OUT=${1:-docs/screenshots}
mkdir -p "$OUT"
D="scripts/dev-drive.sh"
shot() { sleep "${2:-0.8}"; $D shot "$OUT/$1.png" >/dev/null && echo "  $1.png"; }

$D launch --seed-demo
$D cmd open-center; $D cmd select:2;            shot panel-light 1.2
$D cmd mods:cmd;                                 shot panel-cmd-held 0.5
$D cmd mods:none; $D cmd query:swift;            shot panel-search
$D cmd query:; $D cmd filter:code;               shot panel-filter-code
$D cmd filter:all; $D cmd select:4; $D cmd preview;  shot panel-expanded-image 1.0
$D cmd preview; $D cmd select:6; $D cmd preview; shot panel-expanded-link 1.0
$D cmd preview; $D cmd select:8; $D cmd preview; shot panel-expanded-color 1.0
$D cmd preview; $D cmd ghost;                    shot panel-ghost
$D cmd appearance:dark; $D cmd select:2;         shot panel-dark
$D cmd appearance:system; $D cmd close; $D cmd clear; $D cmd open-center; shot panel-empty 1.0
$D cmd close; $D cmd settings;                   shot settings-general 1.2
$D cmd settings:privacy;                         shot settings-privacy
$D cmd onboarding;                               shot onboarding-1 1.2
$D kill
echo "done → $OUT"
