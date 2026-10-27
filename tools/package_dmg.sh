#!/usr/bin/env bash
# Build a .dmg disk image of the macOS app: RoboCore.app beside a link to Applications, so it installs by dragging.
#
# Usage:
#   bash tools/package_dmg.sh                                  # builds the macOS app with Flutter if needed
#   bash tools/package_dmg.sh <RoboCore.app> [out] [offline]   # out: robocore-ide-macos.dmg
#
# [offline] is a bundle from tools/make_offline_bundle.sh (build/offline-arm64 or build/offline-x86_64): its
# arduino-cli goes in Contents/MacOS and its board tools and libraries in Contents/Resources/Offline, so the app
# compiles with no internet. There is one bundle, and so one DMG, for each kind of Mac.
#
# The app is then signed again: ad hoc unless SIGN_ID names a Developer ID ("Developer ID Application: …"), which
# also turns on the hardened runtime that notarisation needs. Without a Developer ID other Macs refuse to open it.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

APP=${1:-build/macos/Build/Products/Release/RoboCore.app}
OUT=${2:-robocore-ide-macos.dmg}
OFFLINE=${3:-}
SIGN_ID=${SIGN_ID:--}
if [ ! -d "$APP" ]; then
  flutter build macos --release
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
A="$STAGE/RoboCore.app"
ditto "$APP" "$A"
if [ -n "$OFFLINE" ]; then
  [ -f "$OFFLINE/manifest.json" ] || { echo "error: $OFFLINE has no manifest.json" >&2; exit 1; }
  install -m 755 "$OFFLINE/arduino-cli" "$A/Contents/MacOS/arduino-cli"
  mkdir -p "$A/Contents/Resources/Offline"
  ditto "$OFFLINE" "$A/Contents/Resources/Offline"
  rm "$A/Contents/Resources/Offline/arduino-cli"
fi

sign() {
  if [ "$SIGN_ID" = "-" ]; then
    codesign --force --sign - "$@"
  else
    codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$@"
  fi
}
for f in "$A"/Contents/Frameworks/*; do sign "$f"; done
if [ -f "$A/Contents/MacOS/arduino-cli" ]; then sign "$A/Contents/MacOS/arduino-cli"; fi
sign --entitlements "$ROOT/macos/Runner/Release.entitlements" "$A"
codesign --verify --deep --strict "$A"

ln -s /Applications "$STAGE/Applications"
hdiutil create -volname RoboCore -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
