#!/bin/bash
# scripts/capture.sh <name> [--attach] [--active]: capture the app window into docs/design/captures/<name>.png.
# By default the window is never brought to the front: it is captured by window ID (no keyboard or focus stealing).
# BRAINMERGE_SCREEN=memory|settings|usage|add|edit opens the app on that screen (add/edit: the sheet).
# With BRAINMERGE_HOME or BRAINMERGE_SCREEN, the executable is launched directly (open does not forward the environment).
# --attach: capture the app that is already open, without launching or closing it.
# --active: an active-looking window (colored traffic lights, vivid buttons). Waits until nobody has touched the
#   keyboard or the mouse for 45 s (CAPTURE_IDLE), then brings the app to the front for the capture only and gives
#   the front back to the previous app. After CAPTURE_WAIT seconds (default 600) it captures inactive and says so.
set -e
NAME="${1:-fenetre}"
ATTACH=""; ACTIVE=""
for arg in "${@:2}"; do
  case "$arg" in --attach) ATTACH=1 ;; --active) ACTIVE=1 ;; esac
done
idle_seconds() { ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }'; }
APP=".build/xcode/Build/Products/Debug/Brainmerge.app"
EXE="$APP/Contents/MacOS/Brainmerge"
mkdir -p docs/design/captures
PID=""
launch() { BRAINMERGE_CAPTURE=1 "$EXE" > /dev/null 2>&1 & PID=$!; }
# The demo's own process when we launched it, the app by name otherwise (--attach).
window_id() { swift scripts/window-id.swift "${PID:-Brainmerge}" 2>/dev/null; }
# System Events addresses the process by its PID when we have one: never another copy of Brainmerge that is open.
process_ref() { if [ -n "$PID" ]; then echo "first process whose unix id is $PID"; else echo 'process "Brainmerge"'; fi; }
if [ -z "$ATTACH" ]; then
  pkill -f "$PWD/$EXE" 2>/dev/null || true
  # Only ever a demo home: set, not the real home, and holding the demo's fake Claude and its account apps.
  # A capture of someone's real accounts must be impossible, even when the demo script failed upstream.
  REAL_HOME=$(cd ~ && pwd -P)
  if [ -z "${BRAINMERGE_HOME:-}" ] || [ ! -d "$BRAINMERGE_HOME/Claude.app" ] || [ ! -d "$BRAINMERGE_HOME/Applications/Brainmerge" ] \
     || [ "$(cd "$BRAINMERGE_HOME" 2>/dev/null && pwd -P)" = "$REAL_HOME" ]; then
    echo "capture: refusing to launch outside a demo home (run scripts/demo-home.sh and export what it prints)" >&2; exit 1
  fi
  for attempt in 1 2; do
    launch
    for i in $(seq 1 30); do
      if window_id > /dev/null; then break 2; fi
      sleep 0.5
    done
    echo "window not found (attempt $attempt), retrying" >&2
    if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi
    sleep 1
  done
  window_id > /dev/null || { echo "capture: the demo window never appeared" >&2; [ -n "$PID" ] && kill "$PID" 2>/dev/null; exit 1; }
fi
# Size and position without activation (System Events does not need to be in front for this).
osascript -e "tell application \"System Events\" to tell ($(process_ref)) to set position of window 1 to {80, 80}" \
         -e "tell application \"System Events\" to tell ($(process_ref)) to set size of window 1 to {1080, 700}" > /dev/null 2>&1 || true
sleep "${CAPTURE_DELAY:-1}"   # longer for screens that animate in (the memory graph)
ID=$(window_id)
PREVIOUS=""
if [ -n "$ACTIVE" ]; then
  WAITED=0; IDLE_NEEDED="${CAPTURE_IDLE:-45}"; MAX_WAIT="${CAPTURE_WAIT:-600}"
  while [ "$(idle_seconds)" -lt "$IDLE_NEEDED" ] && [ "$WAITED" -lt "$MAX_WAIT" ]; do sleep 5; WAITED=$((WAITED + 5)); done
  if [ "$(idle_seconds)" -ge "$IDLE_NEEDED" ]; then
    PREVIOUS=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || true)
    osascript -e "tell application \"System Events\" to set frontmost of ($(process_ref)) to true" >/dev/null 2>&1 || true
    sleep 1
  else
    echo "capture: the Mac was never idle for $IDLE_NEEDED s in $MAX_WAIT s, capturing inactive" >&2
  fi
fi
screencapture -x -o -l "$ID" "docs/design/captures/$NAME.png"
if [ -n "$PREVIOUS" ] && [ "$PREVIOUS" != "Brainmerge" ]; then
  osascript -e "tell application \"System Events\" to set frontmost of process \"$PREVIOUS\" to true" >/dev/null 2>&1 || true
fi
if [ -z "$ATTACH" ] && [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi
echo "docs/design/captures/$NAME.png"
