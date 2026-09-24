#!/bin/bash
# scripts/demo-home.sh: prepares a demo HOME and prints the exports to run before scripts/capture.sh
# scripts/demo-home.sh clean DIR: closes the fake Claude, unregisters the launchers, removes the folder
# The fake Claude.app is a binary that sleeps; it carries its own identifier, never the real Claude's.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/Packages/BrainmergeCore"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ "$1" = "clean" ]; then
  DIR="$2"; [ -d "$DIR" ] || exit 0
  # Guard: only delete a recognizable demo folder (fake Claude.app and Brainmerge launchers).
  if [ ! -d "$DIR/Claude.app" ] || [ ! -d "$DIR/Applications/Brainmerge" ]; then echo "not a demo folder: $DIR" >&2; exit 1; fi
  pkill -f "$DIR/Claude.app/Contents/MacOS/Claude" 2>/dev/null || true
  for app in "$DIR"/Applications/Brainmerge/*.app; do [ -d "$app" ] && "$LSREG" -u "$app" > /dev/null 2>&1 || true; done
  rm -rf "$DIR"
  echo "cleaned up: $DIR"
  exit 0
fi

H="$(cd "$(mktemp -d)" && pwd -P)"
# One product per invocation: "--product A --product B" only builds B.
for product in brainmerge launcher; do swift build --package-path "$CORE" --product "$product" > /dev/null 2>&1; done
CLI="$CORE/.build/debug/brainmerge"
APP="$H/Claude.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$H/.claude"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>ch.rubencatalao.brainmerge.demo-claude</string>
  <key>CFBundleName</key><string>Claude</string>
  <key>CFBundleExecutable</key><string>Claude</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.7032.0</string>
  <key>CFBundleIconFile</key><string>electron</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
printf '#include <unistd.h>\nint main(void) { for (;;) pause(); return 0; }\n' > "$H/claude.c"
cc -o "$APP/Contents/MacOS/Claude" "$H/claude.c"
cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns "$APP/Contents/Resources/electron.icns"
export BRAINMERGE_HOME="$H" BRAINMERGE_CLAUDE_APP="$APP"
# Two projects known to the main Claude Code (like on a real Mac: the "projects" keys in ~/.claude.json).
mkdir -p "$H/website" "$H/mobile-app"
printf '{"projects":{"%s/website":{},"%s/mobile-app":{}}}\n' "$H" "$H" > "$H/.claude.json"
"$CLI" brain init > /dev/null
"$CLI" adopt-primary --name Personal > /dev/null
"$CLI" identity add --name Studio --tint pink --note "Design studio" --shared-history > /dev/null
"$CLI" identity add --name Client --tint purple --note "Client work" > /dev/null
"$CLI" identity add --name Work --tint blue --note "Day job" > /dev/null
# A second memory, for the Work account only: what it learns stays apart from the shared one.
"$CLI" brain add --name Work > /dev/null
"$CLI" identity edit work --brain work > /dev/null
# The Client account has its own icon in the Dock (a tinted copy), built for an older Claude: the app offers to update it.
"$CLI" identity edit client --icon distinct > /dev/null
python3 - "$H/Library/Application Support/Brainmerge/state.json" <<'PY3'
import json, sys
path = sys.argv[1]; state = json.load(open(path))
for identity in state["identities"]:
    if identity["slug"] == "client": identity["builtForClaudeVersion"] = "2.7031.0"
state["autoRebuild"] = False   # the app then offers the update instead of doing it on its own
json.dump(state, open(path, "w"), indent=2)
PY3
# A few memories, committed by two accounts, for the Memory screen.
BRAIN="$H/Brain"
mkdir -p "$BRAIN/memory/website" "$BRAIN/memory/mobile-app"
printf '# Pricing decision\n\nKeep the launch offer until October.\n' > "$BRAIN/memory/website/decision_pricing.md"
"$CLI" sync --identity studio > /dev/null
printf '# Memory\n\n- Tests run with swift test.\n' > "$BRAIN/memory/mobile-app/MEMORY.md"
printf '# Feedback\n\nAlways run the suite before a commit.\n' > "$BRAIN/memory/mobile-app/feedback_tests.md"
"$CLI" sync --identity personal > /dev/null
printf '\nLaunch offer extended to November.\n' >> "$BRAIN/memory/website/decision_pricing.md"
"$CLI" sync --identity studio > /dev/null
# Demo transcripts (usage): a few assistant messages per day over two weeks, two projects, two models.
python3 - "$H" <<'PY2'
import json, os, sys, datetime, random
home = sys.argv[1]; random.seed(7)
def lines(project, days, per_day, model, out):
    now = datetime.datetime.now(datetime.timezone.utc); rows = []
    for back in range(days):
        for i in range(per_day):
            t = now - datetime.timedelta(days=back, hours=i * 2 + 1)
            rows.append(json.dumps({"type": "assistant", "timestamp": t.strftime("%Y-%m-%dT%H:%M:%S.000Z"), "uuid": f"{project}-{back}-{i}",
                "message": {"id": f"msg_{project}_{back}_{i}", "model": model, "role": "assistant",
                            "usage": {"input_tokens": 12, "cache_creation_input_tokens": 800, "cache_read_input_tokens": 14000 + random.randint(0, 9000), "output_tokens": out + random.randint(0, out)}}}))
    return "\n".join(rows) + "\n"
for profile, project, days, per_day, model, out in [(".claude", "-website", 14, 6, "claude-fable-5-1", 900), (".claude", "-mobile-app", 9, 3, "claude-opus-5-5", 400),
                                                     (".claude-client", "-client-site", 5, 4, "claude-fable-5-1", 600)]:
    d = os.path.join(home, profile, "projects", "-Users-demo" + project); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "session.jsonl"), "w").write(lines(project, days, per_day, model, out))
PY2
# Two accounts open: the primary one (the fake Claude, launched by its exact path) and ClientStudio (via its launcher).
"$APP/Contents/MacOS/Claude" > /dev/null 2>&1 &
"$CLI" identity launch studio > /dev/null
sleep 1
echo "After the demo: scripts/demo-home.sh clean '$H'  (closes the fake Claude, unregisters the launchers, removes the folder)" >&2
echo "export BRAINMERGE_HOME='$H' BRAINMERGE_CLAUDE_APP='$APP'"
