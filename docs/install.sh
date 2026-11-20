#!/bin/sh
# Installs NH Red Light Block into /Applications and opens it.
# Usage: curl -fsSL https://nhaasmann.github.io/nh-red-light-block/install.sh | sh
set -e
URL="https://github.com/nhaasmann/nh-red-light-block/releases/latest/download/NH-Red-Light-Block.dmg"
APP="NH Red Light Block.app"
DEST="${NH_DEST:-/Applications}"

[ "$(uname)" = "Darwin" ] || { echo "This app is for macOS only."; exit 1; }
TMP="$(mktemp -d)"
trap 'hdiutil detach "$TMP/mnt" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "Downloading NH Red Light Block..."
curl -fsSL "$URL" -o "$TMP/app.dmg"
hdiutil attach "$TMP/app.dmg" -nobrowse -quiet -mountpoint "$TMP/mnt"

echo "Installing to $DEST..."
[ -n "$NH_DEST" ] || pkill -x RedLightBlock 2>/dev/null || true
rm -rf "$DEST/$APP"
cp -R "$TMP/mnt/$APP" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

[ -n "$NH_DEST" ] || open "$DEST/$APP"
echo "Done. Look for the sun or moon in your menu bar, top right."
