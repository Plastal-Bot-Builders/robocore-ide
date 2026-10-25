#!/usr/bin/env bash
# Builds the macOS app's offline bundle for one kind of Mac, so a school can compile and upload with no internet:
# arduino-cli, the board tools (the Arduino Uno; the ESP32-S3 for the RoboCore V2 and the classic ESP32 for the
# DevKit and NodeMCU, without the other ESP32 chips, which would add about 4 GB) and the libraries the IDE offers.
# tools/package_dmg.sh puts it in the app; lib/hw/local_compiler_native.dart unpacks a board's tools the first time
# that board is built.
#
# Usage:
#   bash tools/make_offline_bundle.sh arm64|x86_64 [out]     (out: build/offline-<arch>)
#
# It downloads about 2.5 GB (the ESP32 package brings every chip's tools; the extra ones are then removed). Set
# SEED=~/Library/Arduino15 to start from an Arduino install's downloads instead (cloned, never changed). On an
# Apple-silicon Mac the Intel bundle is made with the Intel arduino-cli under Rosetta.
set -euo pipefail

ARCH=${1:?usage: make_offline_bundle.sh arm64|x86_64 [out]}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${2:-$ROOT/build/offline-$ARCH}

# The versions this Mac app builds with. (server/Dockerfile pins the compile server's; keep them close.)
CLI_VERSION=1.5.1
ESP32_VERSION=3.3.11
AVR_VERSION=1.8.8
LIBS=("ESP32Servo@3.2.1" "Adafruit NeoPixel@1.12.3" "NewPing@1.9.7" "LiquidCrystal I2C@1.1.2")
# The ESP32 tools RoboCore's boards use; the rest of the ESP32 package goes.
ESP32_KEEP=(esp-x32 esp32s3-libs esp32-libs esptool_py mklittlefs mkspiffs)

case $ARCH in
  arm64) CLI_ASSET=macOS_ARM64; RUN=() ;;
  x86_64) CLI_ASSET=macOS_64bit; RUN=(arch -x86_64) ;;
  *) echo "error: arch is arm64 or x86_64" >&2; exit 1 ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
echo "== arduino-cli $CLI_VERSION ($ARCH)"
f="arduino-cli_${CLI_VERSION}_${CLI_ASSET}.tar.gz"
curl -fsSL -o "$WORK/$f" "https://downloads.arduino.cc/arduino-cli/$f"
curl -fsSL -o "$WORK/sums.txt" "https://downloads.arduino.cc/arduino-cli/${CLI_VERSION}-checksums.txt"
(cd "$WORK" && grep " $f\$" sums.txt | shasum -a 256 -c -)
tar -xzf "$WORK/$f" -C "$WORK" arduino-cli
CLI=("${RUN[@]+"${RUN[@]}"}" "$WORK/arduino-cli")

export ARDUINO_DIRECTORIES_DATA="$WORK/Arduino15"
export ARDUINO_DIRECTORIES_USER="$WORK/user"
export ARDUINO_DIRECTORIES_DOWNLOADS="$WORK/downloads"
export ARDUINO_BUILD_CACHE_PATH="$WORK/cache"
export ARDUINO_BOARD_MANAGER_ADDITIONAL_URLS=https://espressif.github.io/arduino-esp32/package_esp32_index.json
mkdir -p "$ARDUINO_DIRECTORIES_DATA" "$ARDUINO_DIRECTORIES_DOWNLOADS"
if [ -n "${SEED:-}" ] && [ -d "$SEED/staging" ]; then
  echo "== reusing downloads from $SEED"
  cp -cR "$SEED/staging/." "$ARDUINO_DIRECTORIES_DOWNLOADS/" # APFS clones: no copy, no extra space
  [ -f "$SEED/library_index.json" ] && cp -c "$SEED/library_index.json"* "$ARDUINO_DIRECTORIES_DATA/"
fi

echo "== board packages"
"${CLI[@]}" core update-index
"${CLI[@]}" core install "arduino:avr@$AVR_VERSION" "esp32:esp32@$ESP32_VERSION"
echo "== libraries"
[ -f "$ARDUINO_DIRECTORIES_DATA/library_index.json" ] || "${CLI[@]}" lib update-index
"${CLI[@]}" lib install "${LIBS[@]}"

echo "== trimming the ESP32 package to the ESP32 and ESP32-S3"
for d in "$ARDUINO_DIRECTORIES_DATA/packages/esp32/tools"/*; do
  keep=0
  for k in "${ESP32_KEEP[@]}"; do [ "$(basename "$d")" = "$k" ] && keep=1; done
  [ $keep = 1 ] || rm -rf "$d"
done

# A first build of each kind also fetches arduino-cli's own helper tools (packages/builtin) and proves the trimmed
# tools are enough.
echo "== test builds"
mkdir -p "$WORK/Blink"
printf 'void setup() { pinMode(13, OUTPUT); }\nvoid loop() { digitalWrite(13, !digitalRead(13)); delay(500); }\n' > "$WORK/Blink/Blink.ino"
for fqbn in "arduino:avr:uno" \
  "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=enabled,CPUFreq=240" \
  "esp32:esp32:esp32:FlashSize=4M,PartitionScheme=default"; do
  "${CLI[@]}" compile --fqbn "$fqbn" --build-path "$WORK/build-${fqbn//[:=,]/_}" "$WORK/Blink" | grep -E 'Sketch uses'
done

echo "== packing into $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/libraries"
cp "$WORK/arduino-cli" "$OUT/"
D=$ARDUINO_DIRECTORIES_DATA
export XZ_OPT=-T0
tar -C "$D" -cJf "$OUT/base.tar.xz" package_index.json package_esp32_index.json packages/builtin
tar -C "$D" -cJf "$OUT/uno.tar.xz" packages/arduino
tar -C "$D" -cJf "$OUT/esp32.tar.xz" packages/esp32
cp -R "$ARDUINO_DIRECTORIES_USER/libraries/." "$OUT/libraries/"
cp -R "$ROOT/firmware/RoboCore" "$OUT/libraries/RoboCore"
cat > "$OUT/manifest.json" <<EOF
{
  "arch": "$ARCH",
  "arduinoCli": "$CLI_VERSION",
  "packs": {
    "base": {"file": "base.tar.xz", "version": "$CLI_VERSION"},
    "uno": {"file": "uno.tar.xz", "version": "arduino:avr@$AVR_VERSION", "boards": ["uno"]},
    "esp32": {"file": "esp32.tar.xz", "version": "esp32:esp32@$ESP32_VERSION", "boards": ["v2", "devkit", "nodemcu"]}
  }
}
EOF
du -sh "$OUT"/* | sort -h
echo "done: $OUT"
