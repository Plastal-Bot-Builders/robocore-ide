#!/usr/bin/env bash
# Build an installable .rpm package for Fedora and other RPM-based Linux systems.
#
# Usage:
#   bash tools/package_rpm.sh           # builds the Linux app with Flutter if needed, then packages the RPM
#   bash tools/package_rpm.sh <bundle>  # packages an existing Flutter Linux bundle directory
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "error: rpmbuild is not installed. On Fedora: sudo dnf install rpm-build" >&2
  exit 1
fi

# Read version and build number from pubspec.yaml (e.g. 1.0.0+1 -> version 1.0.0, release 1).
RAW_VER=$(awk '/^version:/ {print $2; exit}' pubspec.yaml)
VERSION=${RAW_VER%%+*}
RELEASE=${RAW_VER#*+}
if [ "$RELEASE" = "$RAW_VER" ] || [ -z "$RELEASE" ]; then
  RELEASE=1
fi
VERSION=${VERSION//-/_}

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) FLUTTER_ARCH=x64; RPM_ARCH=x86_64 ;;
  aarch64|arm64) FLUTTER_ARCH=arm64; RPM_ARCH=aarch64 ;;
  *) FLUTTER_ARCH=$ARCH; RPM_ARCH=$ARCH ;;
esac

BUNDLE_DIR=${1:-"$ROOT/build/linux/$FLUTTER_ARCH/release/bundle"}

if [ ! -x "$BUNDLE_DIR/robocore" ] && [ ! -x "$BUNDLE_DIR/robocore_ide" ]; then
  flutter build linux --release
fi

if [ -x "$BUNDLE_DIR/robocore" ]; then
  BIN_NAME="robocore"
elif [ -x "$BUNDLE_DIR/robocore_ide" ]; then
  BIN_NAME="robocore_ide"
else
  echo "error: Linux bundle executable not found in $BUNDLE_DIR" >&2
  exit 1
fi

BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd)
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/robocore-rpm.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

SPEC="$WORK_DIR/SPECS/robocore-ide.spec"
cat > "$SPEC" <<EOF
%global debug_package %{nil}
%global _build_id_links none
%global __strip /bin/true
%global __os_install_post %{nil}
%undefine _source_date_epoch_from_changelog
%undefine __brp_strip
%undefine __brp_strip_comment_note
%undefine __brp_strip_lto
%undefine __brp_check_rpaths

Name:           robocore-ide
Version:        $VERSION
Release:        $RELEASE
Summary:        RoboCore IDE — build, code and run sketches for the RoboCore classroom robot
License:        MIT
URL:            https://github.com/Plastal-Bot-Builders/robocore-ide
AutoReqProv:    no
Requires:       gtk3

%description
Build, code and upload sketches to the RoboCore classroom robot, with blocks or C++.
Includes the blocks editor, C++ editor, built-in sketch checker, and simulated RoboCore board.

%install
rm -rf %{buildroot}
install -d %{buildroot}/usr/lib/robocore-ide
cp -a "$BUNDLE_DIR"/. %{buildroot}/usr/lib/robocore-ide/
chmod 0755 %{buildroot}/usr/lib/robocore-ide/$BIN_NAME

install -d %{buildroot}/usr/bin
ln -s ../lib/robocore-ide/$BIN_NAME %{buildroot}/usr/bin/robocore
ln -s ../lib/robocore-ide/$BIN_NAME %{buildroot}/usr/bin/robocore-ide

install -d %{buildroot}/usr/share/applications
cat > %{buildroot}/usr/share/applications/com.robocore.robocore_ide.desktop <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=RoboCore
GenericName=Robotics IDE
Comment=Build, code and upload sketches to the RoboCore robot, with blocks or C++.
Exec=robocore %U
Icon=robocore-ide
Terminal=false
Categories=Development;IDE;Education;Robotics;
StartupWMClass=com.robocore.robocore_ide
DESKTOP

install -d %{buildroot}/usr/share/icons/hicolor/64x64/apps
install -d %{buildroot}/usr/share/icons/hicolor/192x192/apps
install -d %{buildroot}/usr/share/icons/hicolor/512x512/apps
install -m 0644 "$ROOT/web/favicon.png" %{buildroot}/usr/share/icons/hicolor/64x64/apps/robocore-ide.png
install -m 0644 "$ROOT/web/icons/Icon-192.png" %{buildroot}/usr/share/icons/hicolor/192x192/apps/robocore-ide.png
install -m 0644 "$ROOT/web/icons/Icon-512.png" %{buildroot}/usr/share/icons/hicolor/512x512/apps/robocore-ide.png
if [ -f "$ROOT/linux/runner/resources/app_icon.png" ]; then
  install -d %{buildroot}/usr/share/icons/hicolor/256x256/apps
  install -m 0644 "$ROOT/linux/runner/resources/app_icon.png" %{buildroot}/usr/share/icons/hicolor/256x256/apps/robocore-ide.png
fi

%files
/usr/bin/robocore
/usr/bin/robocore-ide
/usr/lib/robocore-ide
/usr/share/applications/com.robocore.robocore_ide.desktop
/usr/share/icons/hicolor/*/apps/robocore-ide.png
EOF

rpmbuild -bb \
  --target "$RPM_ARCH" \
  --define "_topdir $WORK_DIR" \
  "$SPEC"

OUT_DIR="$ROOT/build/linux"
mkdir -p "$OUT_DIR"
RPM_FILE=$(find "$WORK_DIR/RPMS" -name '*.rpm' -type f | head -n 1)
if [ -z "$RPM_FILE" ]; then
  echo "error: rpmbuild did not produce an .rpm file" >&2
  exit 1
fi

DEST="$OUT_DIR/$(basename "$RPM_FILE")"
cp -f "$RPM_FILE" "$DEST"
cp -f "$RPM_FILE" "$ROOT/robocore-ide-linux-$FLUTTER_ARCH.rpm"
echo "Built RPM: $DEST"
echo "Release RPM: $ROOT/robocore-ide-linux-$FLUTTER_ARCH.rpm"
