#!/bin/bash
# scripts/release.sh: builds Brainmerge for distribution and packs it in a clean DMG (painted background,
# app on the left, Applications on the right, volume icon).
#
# Two ways to sign:
# - Developer ID, notarized (what people should download): set BRAINMERGE_TEAM_ID to your Apple team, be signed
#   in to Xcode with the team's Account Holder (Xcode signs with a cloud-managed Developer ID certificate), and
#   give notarytool an App Store Connect API key through NOTARY_KEY_ID, NOTARY_ISSUER_ID and NOTARY_KEY_PATH
#   (the .p8 file). The app, then the disk image, are notarized and stapled: Gatekeeper opens them without a prompt.
# - Ad hoc (anyone, no Apple account): leave BRAINMERGE_TEAM_ID unset. macOS then asks to confirm the first opening.
#
# Output: dist/Brainmerge-<version>.dmg and dist/Brainmerge.dmg (the same file, the name the website links to).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep MARKETING_VERSION project.yml | head -1 | awk '{print $2}' | tr -d '"')
TEAM="${BRAINMERGE_TEAM_ID:-}"
WORK=.build/release-work
rm -rf dist "$WORK" && mkdir -p dist "$WORK"
xcodegen generate >/dev/null

# NOTARIZE_LATER=1: the Developer ID build is submitted to Apple without waiting (useful while Apple's queue is slow).
# The disk image goes out signed; once Apple accepts it, Gatekeeper finds the ticket online, and
# `xcrun stapler staple dist/Brainmerge-<version>.dmg` staples it for offline checks.
submit_later() {   # submit_later <file>: submits and records the submission id in dist/notary-pending.txt
  local log="$WORK/notary-$(basename "$1").log"
  xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --no-wait > "$log" 2>&1 \
    || { cat "$log" >&2; exit 1; }
  local id; id=$(grep -m1 -E '^ *id:' "$log" | awk '{print $2}')
  [ -n "$id" ] || { cat "$log" >&2; exit 1; }
  echo "$(basename "$1") $id" >> dist/notary-pending.txt
  echo "Submitted for notarization: $(basename "$1") ($id)"
}

notarize() {   # notarize <file>: submits, waits, fails loudly on anything but Accepted
  local log="$WORK/notary-$(basename "$1").log"
  xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait --timeout 60m > "$log" 2>&1 || true
  if ! grep -q "status: Accepted" "$log"; then
    echo "Notarization of $(basename "$1") did not succeed:" >&2; cat "$log" >&2
    local id; id=$(grep -m1 -E '^ *id:' "$log" | awk '{print $2}')
    [ -n "$id" ] && xcrun notarytool log "$id" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >&2 || true
    exit 1
  fi
  echo "Notarized: $(basename "$1")"
}

if [ -n "$TEAM" ]; then
  : "${NOTARY_KEY_ID:?set NOTARY_KEY_ID}" "${NOTARY_ISSUER_ID:?set NOTARY_ISSUER_ID}" "${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH}"
  echo "Developer ID build for team $TEAM"
  xcodebuild -project Brainmerge.xcodeproj -scheme Brainmerge -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$WORK/Brainmerge.xcarchive" -derivedDataPath "$WORK/dd" -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development" archive > "$WORK/archive.log" 2>&1 \
    || { tail -n 30 "$WORK/archive.log" >&2; exit 1; }
  cat > "$WORK/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
  # The Developer ID certificate is cloud-managed: the export uses the account signed in to Xcode.
  xcodebuild -exportArchive -archivePath "$WORK/Brainmerge.xcarchive" -exportPath "$WORK/export" \
    -exportOptionsPlist "$WORK/export.plist" -allowProvisioningUpdates > "$WORK/export.log" 2>&1 \
    || { tail -n 30 "$WORK/export.log" >&2; exit 1; }
  APP="$WORK/export/Brainmerge.app"
  for f in "$APP" "$APP/Contents/MacOS/brainmerge-cli" "$APP/Contents/MacOS/launcher"; do
    codesign -dv "$f" 2>&1 | grep -q "flags=0x10000(runtime)" || { echo "$f is not signed with the hardened runtime" >&2; exit 1; }
  done
  codesign --verify --deep --strict "$APP"
  if [ -z "${NOTARIZE_LATER:-}" ]; then
    ditto -c -k --keepParent "$APP" "$WORK/Brainmerge.zip"
    notarize "$WORK/Brainmerge.zip"
    xcrun stapler staple "$APP" >/dev/null
    spctl -a -t exec "$APP" || { echo "Gatekeeper still rejects the app" >&2; exit 1; }
  fi
else
  echo "No BRAINMERGE_TEAM_ID: ad hoc signature (macOS will ask people to confirm the first opening)."
  xcodebuild -project Brainmerge.xcodeproj -scheme Brainmerge -configuration Release -derivedDataPath "$WORK/dd" build > "$WORK/build.log" 2>&1 \
    || { tail -n 30 "$WORK/build.log" >&2; exit 1; }
  APP="$WORK/dd/Build/Products/Release/Brainmerge.app"
  codesign --verify --deep --strict "$APP"
fi

# 1. A read-write DMG, with the background and volume icon.
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Brainmerge.app"   # ditto keeps the signature and the stapled ticket intact
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
[ -f docs/brand/dmg-background.png ] || swift scripts/make-dmg-background.swift >/dev/null
cp docs/brand/dmg-background.png "$STAGE/.background/background.png"
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
RW="dist/Brainmerge-rw.dmg"
hdiutil create -volname "Brainmerge" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
rm -rf "$STAGE"

# 2. Layout by the Finder (icon view, positions, background). If Finder automation is denied or slow,
#    the DMG is still valid, just without the layout.
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep "/Volumes/" | sed -E 's/.*(\/Volumes\/.*)/\1/')
[ -f "$MOUNT/.VolumeIcon.icns" ] && SetFile -a C "$MOUNT" 2>/dev/null || true
osascript - "$(basename "$MOUNT")" <<'AS' > /dev/null 2>&1 &
on run argv
  set volumeName to item 1 of argv
  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 140, 860, 568}
      set theViewOptions to the icon view options of container window
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to 112
      set text size of theViewOptions to 13
      set background picture of theViewOptions to file ".background:background.png"
      set position of item "Brainmerge.app" of container window to {165, 215}
      set position of item "Applications" of container window to {495, 215}
      close
      open
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
AS
FINDER=$!
for i in $(seq 1 40); do kill -0 $FINDER 2>/dev/null || break; sleep 0.5; done
if kill -0 $FINDER 2>/dev/null; then kill $FINDER 2>/dev/null || true; echo "Finder layout not applied (automation denied or too slow)."; fi
sync
hdiutil detach "$MOUNT" -quiet || (sleep 2 && hdiutil detach "$MOUNT" -force -quiet)

# 3. Conversion to a compressed, read-only image; with Developer ID, the image is notarized and stapled too.
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "dist/Brainmerge-$VERSION.dmg" >/dev/null
rm -f "$RW"
if [ -n "$TEAM" ] && [ -n "${NOTARIZE_LATER:-}" ]; then
  submit_later "dist/Brainmerge-$VERSION.dmg"   # the image holds the app: one submission covers both
elif [ -n "$TEAM" ]; then
  notarize "dist/Brainmerge-$VERSION.dmg"
  xcrun stapler staple "dist/Brainmerge-$VERSION.dmg" >/dev/null
  spctl -a -t open --context context:primary-signature "dist/Brainmerge-$VERSION.dmg" 2>/dev/null || true
fi
cp "dist/Brainmerge-$VERSION.dmg" dist/Brainmerge.dmg
echo "dist/Brainmerge-$VERSION.dmg"
