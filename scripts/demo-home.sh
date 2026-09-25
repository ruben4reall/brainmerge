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
# Two projects known to the main Claude Code (like on a real Mac: the "projects" keys in ~/.claude.json), and the
# account it records for display (a made-up example.com address: captures never show a real email).
mkdir -p "$H/website" "$H/mobile-app"
printf '{"projects":{"%s/website":{},"%s/mobile-app":{}},"oauthAccount":{"emailAddress":"alex@example.com","displayName":"Alex"}}\n' "$H" "$H" > "$H/.claude.json"
"$CLI" brain init > /dev/null
"$CLI" adopt-primary --name Personal > /dev/null
"$CLI" identity add --name Studio --tint pink --note "Design studio" --shared-history > /dev/null
printf '{"oauthAccount":{"emailAddress":"studio@example.com","displayName":"Alex"}}\n' > "$H/.claude-studio/.claude.json"
"$CLI" identity add --name Client --tint purple --note "Client work" > /dev/null
"$CLI" identity add --name Work --tint blue --note "Day job" > /dev/null
# Personal and Studio have logged in: Claude's storage files exist in their data folders (empty placeholders;
# Brainmerge only looks at the names). Work and Client have not logged in yet.
for data in "$H/Library/Application Support/Claude" "$H/Library/Application Support/Claude-studio"; do
  mkdir -p "$data/IndexedDB/https_claude.ai_0.indexeddb.leveldb" && touch "$data/Cookies"
done
# A second memory, for the Work account only: what it learns stays apart from the shared one.
"$CLI" brain add --name Work > /dev/null
"$CLI" identity edit work --brain work > /dev/null
# The Client account has its own icon in the Dock (a tinted copy), built for an older Claude: the app offers to update it.
# BRAINMERGE_DEMO_UPDATE=0 leaves it current (no update banner), for a clean Accounts screen.
"$CLI" identity edit client --icon distinct > /dev/null
[ "${BRAINMERGE_DEMO_UPDATE:-1}" = "0" ] || python3 - "$H/Library/Application Support/Brainmerge/state.json" <<'PY3'
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
# A richer memory for the graph: notes linked to each other across projects, saved by different accounts.
notes() {   # notes GROUP: writes one account's notes, so each save carries its own author
python3 - "$BRAIN" "$H/Brain-work" "$1" <<'PYNOTES'
import os, sys
brain, work, group = sys.argv[1], sys.argv[2], sys.argv[3]
def note(root, path, text):
    full = os.path.join(root, path); os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write(text)
groups = {
  "studio": {
    "memory/website/MEMORY.md": "- [Pricing](decision_pricing.md)\n- [Brand voice](feedback_voice.md)\n- [Launch plan](project_launch_plan.md)\n- [Hosting](reference_hosting.md)\n",
    "memory/website/feedback_voice.md": "Short sentences, no jargon. Same voice as [[design-system/tokens|the design tokens]] describe.\n",
    "memory/website/project_launch_plan.md": "Launch on the 14th. Depends on [[decision_pricing]] and [[checkout_flow]].\n",
    "memory/website/reference_hosting.md": "Static site, deploys on push. See [[deploy_checklist]].\n",
    "memory/design-system/MEMORY.md": "- [Tokens](tokens.md)\n- [Type scale](type_scale.md)\n- [Icons](icons.md)\n",
    "memory/design-system/tokens.md": "One accent color. Spacing on a 4 pt grid. Used by [[website/MEMORY]] and [[mobile-app/MEMORY]].\n",
    "memory/design-system/type_scale.md": "Five sizes. Titles in the serif. See [[tokens]].\n",
    "memory/design-system/icons.md": "Line icons, 1.5 pt stroke. Match [[type_scale]].\n",
  },
  "personal": {
    "memory/mobile-app/checkout_flow.md": "Three steps, Apple Pay first. Prices from [[decision_pricing]].\n",
    "memory/mobile-app/project_offline.md": "Cache the last sync; conflicts resolved per field. Related: [[checkout_flow]].\n",
    "memory/mobile-app/reference_api.md": "REST, versioned. Errors as sentences. See [[project_offline]].\n",
    "memory/mobile-app/deploy_checklist.md": "Bump the build, run [[feedback_tests]], then upload.\n",
    "memory/mobile-app/MEMORY.md": "- [Tests](feedback_tests.md)\n- [Checkout](checkout_flow.md)\n- [Offline](project_offline.md)\n- [API](reference_api.md)\n- [Deploy](deploy_checklist.md)\n",
  },
  "client": {
    "memory/client-site/MEMORY.md": "- [Brief](project_brief.md)\n- [Feedback](feedback_client.md)\n- [Timeline](project_timeline.md)\n",
    "memory/client-site/project_brief.md": "Portfolio site, four pages. Reuse [[design-system/tokens|our tokens]].\n",
    "memory/client-site/feedback_client.md": "Prefers fewer words and bigger images. See [[project_brief]].\n",
    "memory/client-site/project_timeline.md": "Review on Friday, launch the week after. Depends on [[feedback_client]].\n",
  },
}
if group == "work":
    note(work, "memory/intranet/MEMORY.md", "- [Access](reference_access.md)\n- [Release](project_release.md)\n")
    note(work, "memory/intranet/reference_access.md", "Single sign-on only. See [[project_release]].\n")
    note(work, "memory/intranet/project_release.md", "Monthly, on the first Tuesday.\n")
else:
    for path, text in groups[group].items(): note(brain, path, text)
PYNOTES
"$CLI" sync --identity "$1" > /dev/null
}
for group in studio personal client work; do notes "$group"; done
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
