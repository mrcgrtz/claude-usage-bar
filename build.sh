#!/bin/sh
# Builds ClaudeUsageBar.app into ./build. Run with --install to copy it to ~/Applications,
# or with --dmg to make build/ClaudeUsageBar.dmg for a release. GitHub runs --dmg when a version tag is pushed.
set -eu

cd "$(dirname "$0")"
APP=build/ClaudeUsageBar.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# A universal binary runs natively on Intel Macs and Macs with Apple silicon.
for ARCH in x86_64 arm64; do
  xcrun swiftc -O -swift-version 6 -target "$ARCH-apple-macos14" \
    Sources/main.swift -o "build/ClaudeUsageBar-$ARCH"
done
lipo -create build/ClaudeUsageBar-x86_64 build/ClaudeUsageBar-arm64 \
  -output "$APP/Contents/MacOS/ClaudeUsageBar"
rm build/ClaudeUsageBar-x86_64 build/ClaudeUsageBar-arm64

cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/"
# Optional custom menu bar icon (black on transparent, used as a template image).
[ -f claude-icon.png ] && cp claude-icon.png "$APP/Contents/Resources/"

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/ClaudeUsageBar.app
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/ClaudeUsageBar.app"
fi

if [ "${1:-}" = "--dmg" ]; then
  STAGE=build/dmg
  MOUNT="$PWD/build/dmg-mount"
  RW=build/ClaudeUsageBar-rw.dmg

  # The link to /Applications lets users install the app with one drag.
  # The window layout comes from DMGLayout.DS_Store, which scripts/make-dmg-layout.sh saves with Finder.
  rm -rf "$STAGE" "$MOUNT" "$RW" build/ClaudeUsageBar.dmg
  mkdir -p "$STAGE/.background"
  ditto "$APP" "$STAGE/ClaudeUsageBar.app"
  ln -s /Applications "$STAGE/Applications"
  cp DMGBackground.tiff "$STAGE/.background/"
  cp DMGLayout.DS_Store "$STAGE/.DS_Store"

  # macOS 27 deprecates hdiutil, but older macOS versions do not have "diskutil image".
  if diskutil image create from -h >/dev/null 2>&1; then
    # "diskutil image create from" only copies disks, so make a blank volume and fill it.
    # The volume gets 20 MB more than the files need, for the file system.
    SIZE=$(( $(du -sk "$STAGE" | cut -f1) * 1024 + 20 * 1024 * 1024 ))
    diskutil image create blank --format RAW --size "$SIZE" --volumeName ClaudeUsageBar "$RW"
    # A private mount point does not clash with a ClaudeUsageBar volume that is already open.
    mkdir -p "$MOUNT"
    diskutil image attach --nobrowse --mountPoint "$MOUNT" "$RW" >/dev/null
    ditto "$STAGE" "$MOUNT"
    sync
    diskutil eject "$MOUNT" >/dev/null
    diskutil image create from --format UDZO "$RW" build/ClaudeUsageBar.dmg
  else
    hdiutil create -volname ClaudeUsageBar -srcfolder "$STAGE" -format UDZO build/ClaudeUsageBar.dmg
  fi
  rm -rf "$STAGE" "$MOUNT" "$RW"
  echo "Made build/ClaudeUsageBar.dmg"
fi
