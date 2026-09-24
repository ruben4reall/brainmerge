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
launch() {
  if [ -n "$BRAINMERGE_HOME" ] || [ -n "$BRAINMERGE_SCREEN" ]; then "$EXE" > /dev/null 2>&1 & PID=$!; else open -g -n "$APP"; fi
}
window_id() { swift scripts/window-id.swift 2>/dev/null; }
if [ -z "$ATTACH" ]; then
  pkill -f "$EXE" 2>/dev/null || true
  for attempt in 1 2; do
    launch
    for i in $(seq 1 30); do
      if window_id > /dev/null; then break 2; fi
      sleep 0.5
    done
    echo "window not found (attempt $attempt), retrying" >&2
    if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; else pkill -f "$EXE" 2>/dev/null || true; fi
    sleep 1
  done
fi
# Size and position without activation (System Events does not need to be in front for this).
osascript <<'AS' > /dev/null 2>&1 || true
tell application "System Events"
  tell process "Brainmerge"
    set position of window 1 to {80, 80}
    set size of window 1 to {1080, 700}
  end tell
end tell
AS
sleep 1
ID=$(window_id)
PREVIOUS=""
if [ -n "$ACTIVE" ]; then
  WAITED=0; IDLE_NEEDED="${CAPTURE_IDLE:-45}"; MAX_WAIT="${CAPTURE_WAIT:-600}"
  while [ "$(idle_seconds)" -lt "$IDLE_NEEDED" ] && [ "$WAITED" -lt "$MAX_WAIT" ]; do sleep 5; WAITED=$((WAITED + 5)); done
  if [ "$(idle_seconds)" -ge "$IDLE_NEEDED" ]; then
    PREVIOUS=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || true)
    osascript -e 'tell application "System Events" to set frontmost of process "Brainmerge" to true' >/dev/null 2>&1 || true
    sleep 1
  else
    echo "capture: the Mac was never idle for $IDLE_NEEDED s in $MAX_WAIT s, capturing inactive" >&2
  fi
fi
screencapture -x -o -l "$ID" "docs/design/captures/$NAME.png"
if [ -n "$PREVIOUS" ] && [ "$PREVIOUS" != "Brainmerge" ]; then
  osascript -e "tell application \"System Events\" to set frontmost of process \"$PREVIOUS\" to true" >/dev/null 2>&1 || true
fi
if [ -z "$ATTACH" ]; then
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; else pkill -f "$EXE" 2>/dev/null || true; fi
fi
echo "docs/design/captures/$NAME.png"
