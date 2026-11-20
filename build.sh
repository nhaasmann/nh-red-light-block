#!/bin/bash
# Builds dist/NH Red Light Block.app (release, ad-hoc signed) and dist/NH Red Light Block.dmg.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/NH Red Light Block.app"
DMG="dist/NH Red Light Block.dmg"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RedLightBlock"

# App icon: NH brand SVG -> .icns
if [ ! -f Resources/AppIcon.icns ] || [ Scripts/make_icon.py -nt Resources/AppIcon.icns ]; then
  python3 Scripts/make_icon.py
  swift Scripts/svg2png.swift Resources/brand/AppIcon.svg Resources/icon_1024.png 1024
  SET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon_1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/icon_1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o Resources/AppIcon.icns
fi

rm -rf dist; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RedLightBlock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

# Disk image: the app next to an Applications shortcut, for drag-to-install.
STAGE="$(mktemp -d)/NH Red Light Block"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NH Red Light Block" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $(pwd)/$APP"
echo "Built $(pwd)/$DMG"
