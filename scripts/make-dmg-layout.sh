#!/bin/sh
# Saves the Finder layout of the DMG window to DMGLayout.DS_Store. build.sh copies this file into the DMG,
# so the build needs no Finder and also runs on GitHub. Run this script on a Mac again when the window changes.
set -eu

cd "$(dirname "$0")/.."
VOLUME=/Volumes/ClaudeUsageBar
IMAGE=build/layout.dmg
if [ -d "$VOLUME" ]; then
  echo "Eject $VOLUME first." >&2
  exit 1
fi

mkdir -p build
rm -f "$IMAGE"
# macOS 27 deprecates hdiutil, but older macOS versions do not have "diskutil image".
if diskutil image create from -h >/dev/null 2>&1; then
  diskutil image create blank --format RAW --size 20m --volumeName ClaudeUsageBar "$IMAGE" >/dev/null
  diskutil image attach "$IMAGE" >/dev/null
else
  hdiutil create -size 20m -fs HFS+ -volname ClaudeUsageBar "$IMAGE" >/dev/null
  hdiutil attach "$IMAGE" >/dev/null
fi

# Finder saves the position of each item by its name, so an empty folder can stand in for the app.
mkdir -p "$VOLUME/ClaudeUsageBar.app" "$VOLUME/.background"
ln -s /Applications "$VOLUME/Applications"
cp DMGBackground.tiff "$VOLUME/.background/"

# The icon positions match the background, which scripts/make-dmg-background.swift draws.
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "ClaudeUsageBar"
    open
    -- Finder ignores the bounds when the window of a new volume is not open yet.
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set bounds of container window to {200, 120, 840, 548}
    set options to icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 112
    set text size of options to 13
    set background picture of options to file ".background:DMGBackground.tiff"
    set position of item "ClaudeUsageBar.app" of container window to {160, 215}
    set position of item "Applications" of container window to {480, 215}
    update without registering applications
    set bounds of container window to {200, 120, 840, 548}
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync

cp "$VOLUME/.DS_Store" DMGLayout.DS_Store
diskutil eject "$VOLUME" >/dev/null
rm -f "$IMAGE"
echo "Saved DMGLayout.DS_Store"
