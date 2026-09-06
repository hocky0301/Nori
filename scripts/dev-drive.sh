#!/bin/zsh
# Dev driver for Nori: launch/kill a debug build, send debug commands, capture the panel.
# Env: NORI_DD (derived data dir with Build/Products/Debug/Nori.app), NORI_CHANNEL (isolates instances).
set -e
DD=${NORI_DD:-$(cd "$(dirname "$0")/.." && pwd)/DerivedData}
CHANNEL=${NORI_CHANNEL:-}
APP=$DD/Build/Products/Debug/Nori.app
PIDFILE=$DD/nori.pid
NOTE="io.github.hocky0301.Nori.debug${CHANNEL:+.$CHANNEL}"

post() {
  swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name(\"$NOTE\"), object: \"$1\", userInfo: nil, deliverImmediately: true)" 2>/dev/null
}

case "$1" in
  launch)
    # Launch through LaunchServices: a direct exec from this shell cannot reach the window server.
    if [ -f "$PIDFILE" ]; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; fi
    shift
    BEFORE=$(pgrep -x Nori | sort)
    open -n "$APP" --args --in-memory ${CHANNEL:+--debug-channel=$CHANNEL} "$@"
    sleep 1.5
    AFTER=$(pgrep -x Nori | sort)
    NEWPID=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | head -1)
    if [ -z "$NEWPID" ]; then echo "Nori failed to start"; exit 1; fi
    echo "$NEWPID" > "$PIDFILE"
    echo "Nori running (pid $NEWPID, channel '${CHANNEL:-default}')"
    ;;
  kill) [ -f "$PIDFILE" ] && { kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; }; echo killed ;;
  cmd) post "$2" ;;
  windows)
    PID=$(cat "$PIDFILE" 2>/dev/null || echo 0)
    swift -e "import AppKit
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[\"kCGWindowOwnerPID\"] as? NSNumber)?.intValue == $PID {
      print((w[\"kCGWindowNumber\"] as? NSNumber)?.intValue ?? 0, w[\"kCGWindowLayer\"] ?? \"?\", w[\"kCGWindowBounds\"] ?? \"?\")
    }" 2>/dev/null
    ;;
  shot)
    # $2 = output png [$3 = 'largest' (default) | 'smallest']. Captures this instance's on-screen window.
    PID=$(cat "$PIDFILE" 2>/dev/null || echo 0)
    WID=$(swift -e "import AppKit
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    var best = (0, \"${3:-largest}\" == \"smallest\" ? Double.greatestFiniteMagnitude : 0.0)
    for w in list where (w[\"kCGWindowOwnerPID\"] as? NSNumber)?.intValue == $PID {
      let b = w[\"kCGWindowBounds\"] as? [String: Any] ?? [:]
      let area = ((b[\"Width\"] as? NSNumber)?.doubleValue ?? 0) * ((b[\"Height\"] as? NSNumber)?.doubleValue ?? 0)
      let n = (w[\"kCGWindowNumber\"] as? NSNumber)?.intValue ?? 0
      if area < 30 { continue }
      if (\"${3:-largest}\" == \"smallest\" ? area < best.1 : area > best.1) { best = (n, area) }
    }
    print(best.0)" 2>&1 | tail -1)
    if [ "$WID" = "0" ] || [ -z "$WID" ]; then echo "no on-screen window for pid $PID"; exit 1; fi
    screencapture -x -o -l "$WID" "$2" && echo "captured window $WID -> $2"
    ;;
  log)
    log show --predicate 'subsystem == "io.github.hocky0301.Nori"' --last "${2:-2m}" --info --debug --style compact 2>/dev/null | grep -v Filtering | tail -${3:-40}
    ;;
  *) echo "usage: nori.sh launch [--seed-demo] | kill | cmd <open|open-center|close|toggle|seed|clear|settings|settings:TAB|onboarding|onboarding:N|ghost|pause|resume|query:TEXT|filter:NAME|down|up|preview|screenshot:PATH> | windows | shot out.png [largest|smallest] | log [2m] [40]" ;;
esac
