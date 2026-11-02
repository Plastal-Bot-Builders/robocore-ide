#!/usr/bin/env bash
# Gives a release's apps a second name without the version (RoboCore-1.0.2-mac-intel.dmg is also attached as
# RoboCore-mac-intel.dmg, RoboCore-Setup-1.0.2.exe as RoboCore-Setup.exe), so
# https://github.com/<repo>/releases/latest/download/<that name> always fetches the newest version. The website's
# download page (plastalbotbuilders.com/robocore/download) links there. build.yml's release-assets job runs it for
# every version tag; the "Release: names without the version" workflow runs it for an older release.
#
# Usage (with gh signed in, GH_TOKEN and GH_REPO set):
#   bash tools/release_latest_names.sh <tag> <folder with the release's versioned files>
set -euo pipefail

TAG=${1:?usage: release_latest_names.sh <tag> <folder>}
DIR=${2:?usage: release_latest_names.sh <tag> <folder>}
V=${TAG#v}
OUT=$DIR/latest-names
rm -rf "$OUT"
mkdir -p "$OUT"

for f in "$DIR"/RoboCore-*; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  case "$n" in
    "RoboCore-Setup-$V.exe") to=RoboCore-Setup.exe ;;
    "RoboCore-$V-"*) to="RoboCore-${n#"RoboCore-$V-"}" ;;
    *) continue ;; # another version's file, or one that already has its fixed name
  esac
  # A hard link where it can, so the DMGs aren't copied.
  ln "$f" "$OUT/$to" 2>/dev/null || cp "$f" "$OUT/$to"
done

if [ -z "$(ls -A "$OUT")" ]; then
  echo "error: no RoboCore-$V-* files in $DIR" >&2
  exit 1
fi
ls -la "$OUT"
gh release upload "$TAG" "$OUT"/* --clobber
