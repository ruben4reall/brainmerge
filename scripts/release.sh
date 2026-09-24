#!/bin/bash
# scripts/release.sh: archives a Release build, signs it (Developer ID if present, otherwise ad hoc), notarizes if a profile exists,
# and builds a clean DMG: painted background, app icon on the left, Applications folder on the right, volume icon.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep MARKETING_VERSION project.yml | head -1 | awk '{print $2}' | tr -d '"')
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
rm -rf dist .build/release-xcode && mkdir -p dist
xcodegen generate >/dev/null
if [ -n "$IDENTITY" ]; then
  echo "Signing: $IDENTITY"
  xcodebuild -project Brainmerge.xcodeproj -scheme Brainmerge -configuration Release -derivedDataPath .build/release-xcode \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" build 2>&1 | tail -1
else
  echo "No Developer ID identity: ad hoc signature (the app will not pass Gatekeeper for other people)."
  xcodebuild -project Brainmerge.xcodeproj -scheme Brainmerge -configuration Release -derivedDataPath .build/release-xcode build 2>&1 | tail -1
fi
APP=".build/release-xcode/Build/Products/Release/Brainmerge.app"
codesign --verify --deep --strict "$APP"
if [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile brainmerge >/dev/null 2>&1; then
  ditto -c -k --keepParent "$APP" dist/Brainmerge.zip
  xcrun notarytool submit dist/Brainmerge.zip --keychain-profile brainmerge --wait
  xcrun stapler staple "$APP"
  rm dist/Brainmerge.zip
else
  echo "No notarization (missing identity or notarytool profile)."
fi

# 1. A read-write DMG, with the background and volume icon.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
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

# 3. Conversion to a compressed, read-only image.
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "dist/Brainmerge-$VERSION.dmg" >/dev/null
rm -f "$RW"
echo "dist/Brainmerge-$VERSION.dmg"
