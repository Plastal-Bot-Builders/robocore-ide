#!/usr/bin/env bash
# Build a .dmg disk image of the macOS app: RoboCore.app beside a link to Applications, so it installs by dragging.
#
# Usage:
#   bash tools/package_dmg.sh                      # builds the macOS app with Flutter if needed, then the image
#   bash tools/package_dmg.sh <RoboCore.app> [out]  # packages an existing app (out: robocore-ide-macos.dmg)
#
# The app goes in signed as it was built (ad hoc, without a Developer ID). Other Macs then refuse to open it
# until it is signed with a Developer ID and notarised, which is a later step.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

APP=${1:-build/macos/Build/Products/Release/RoboCore.app}
OUT=${2:-robocore-ide-macos.dmg}
if [ ! -d "$APP" ]; then
  flutter build macos --release
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/RoboCore.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname RoboCore -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
echo "wrote $OUT"
