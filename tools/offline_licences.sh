#!/usr/bin/env bash
# Writes the licences of what the macOS app's offline bundle carries (tools/make_offline_bundle.sh runs it):
# THIRD-PARTY-NOTICES.txt, with each program and library, its version, its licence and where its source code is,
# and the full GPL, LGPL and GCC exception texts those licences ask to travel with the programs. The app shows the
# notices in About → Licences (lib/licences.dart); tools/package_dmg.sh also puts them on the disk image.
#
# Usage:
#   bash tools/offline_licences.sh <Arduino15 folder> <libraries folder> <arduino-cli version> <out>
set -euo pipefail

DATA=${1:?usage: offline_licences.sh <Arduino15> <libraries> <arduino-cli version> <out>}
LIBS=$2
CLI_VERSION=$3
OUT=$4
P=$DATA/packages
mkdir -p "$OUT"

# The GNU texts, from the ESP32 toolchain, which carries them all.
G=$(ls -d "$P"/esp32/tools/esp-x32/*/share/licenses/gcc | head -1)
cp "$G/COPYING3" "$OUT/GPL-3.0.txt"
cp "$G/COPYING" "$OUT/GPL-2.0.txt"
cp "$G/COPYING3.LIB" "$OUT/LGPL-3.0.txt"
cp "$G/COPYING.LIB" "$OUT/LGPL-2.1.txt"
cp "$G/COPYING.RUNTIME" "$OUT/GCC-runtime-exception-3.1.txt"

# A package's or tool's version: its one folder.
v() { basename "$(ls -d "$P/$1"/*/ | head -1)"; }
lib() { sed -n "s/^$1=//p" "$LIBS/$2/library.properties"; }
row() { printf '%s %s\n  Licence: %s\n  Source:  %s\n\n' "$1" "$2" "$3" "$4"; }

ESP32=$(v esp32/hardware/esp32)
ESPTOOL=$(v esp32/tools/esptool_py)
{
  cat <<'EOF'
OPEN-SOURCE PROGRAMS AND LIBRARIES IN ROBOCORE IDE FOR MACOS

RoboCore IDE for macOS compiles and uploads sketches on the Mac itself, with the programs and libraries below. They
are not changed: each is as its makers publish it. Their licences are in this folder: GPL-3.0.txt, GPL-2.0.txt,
LGPL-3.0.txt, LGPL-2.1.txt and GCC-runtime-exception-3.1.txt; programs with other licences carry them in their own
folders (in the app: Contents/Resources/Offline, packed in the .tar.xz files, and Offline/libraries).

SOURCE CODE
The GPL and LGPL give you the right to the complete source code of the programs here that use them. It is published
at the address listed for each. For at least three years from the day you received this copy of RoboCore IDE,
Plastal-Bot Builders will also send you that source code, on request, for no more than the cost of sending it. Ask at
https://github.com/Plastal-Bot-Builders/robocore-ide/issues.

COMPILING
EOF
  row "arduino-cli" "$CLI_VERSION" "GPL-3.0" "https://github.com/arduino/arduino-cli/tree/v$CLI_VERSION"
  for t in "$P"/builtin/tools/*; do
    n=$(basename "$t")
    ver=$(v "builtin/tools/$n")
    if [ "$n" = ctags ]; then
      row "ctags (Arduino's build)" "$ver" "GPL-2.0" "https://github.com/arduino/ctags"
    else
      row "$n (part of arduino-cli)" "$ver" "GPL-3.0 (LICENSE.txt beside it)" "https://github.com/arduino/$n"
    fi
  done

  echo "ARDUINO UNO"
  AVR=$(v arduino/hardware/avr)
  row "Arduino AVR core" "$AVR" "LGPL-2.1" "https://github.com/arduino/ArduinoCore-avr/tree/$AVR"
  row "avr-gcc, binutils and avr-libc (Arduino's build)" "$(v arduino/tools/avr-gcc)" \
    "GPL-3.0 with the GCC Runtime Library Exception (GCC), GPL-3.0 (binutils), BSD-3-Clause (avr-libc)" \
    "https://github.com/arduino/toolchain-avr"
  row "avrdude (Arduino's build)" "$(v arduino/tools/avrdude)" "GPL-2.0 (LICENSE.txt beside it)" "https://github.com/avrdudes/avrdude"
  row "dfu-util (Arduino's build)" "$(v arduino/tools/dfu-util)" "GPL-2.0" "https://dfu-util.sourceforge.net"
  row "arduinoOTA" "$(v arduino/tools/arduinoOTA)" "see its source" "https://github.com/arduino/arduinoOTA"

  echo "ROBOCORE V2 AND THE ESP32 BOARDS"
  row "Arduino core for the ESP32" "$ESP32" "LGPL-2.1" "https://github.com/espressif/arduino-esp32/tree/$ESP32"
  row "ESP-IDF libraries for Arduino (esp32-libs, esp32s3-libs)" "$(v esp32/tools/esp32s3-libs)" \
    "Apache-2.0, with some parts under other open licences named in their files" \
    "https://github.com/espressif/esp32-arduino-lib-builder and https://github.com/espressif/esp-idf"
  row "Espressif's GCC toolchain (esp-x32: GCC, binutils, newlib and their libraries)" "$(v esp32/tools/esp-x32)" \
    "GPL-3.0 with the GCC Runtime Library Exception, GPL-2.0, LGPL and others; each text is in its share/licenses" \
    "https://github.com/espressif/crosstool-NG"
  row "esptool" "$ESPTOOL" "GPL-2.0 or later (LICENSE beside it)" "https://github.com/espressif/esptool/tree/v$ESPTOOL"
  row "mklittlefs" "$(v esp32/tools/mklittlefs)" "MIT" "https://github.com/earlephilhower/mklittlefs"
  row "mkspiffs" "$(v esp32/tools/mkspiffs)" "MIT" "https://github.com/igrr/mkspiffs"

  echo "LIBRARIES (in Offline/libraries)"
  row "ESP32Servo" "$(lib version ESP32Servo)" "LGPL-2.1 or later (src/ESP32Servo.h)" "https://github.com/madhephaestus/ESP32Servo"
  row "Adafruit NeoPixel" "$(lib version Adafruit_NeoPixel)" "LGPL-3.0 (COPYING beside it)" "https://github.com/adafruit/Adafruit_NeoPixel"
  row "NewPing" "$(lib version NewPing)" "its author's terms in src/NewPing.h: use as is; no forks or changed copies without permission" \
    "https://bitbucket.org/teckel12/arduino-new-ping"
  row "LiquidCrystal I2C" "$(lib version LiquidCrystal_I2C)" "none stated" "$(lib url LiquidCrystal_I2C)"
  row "RoboCore" "$(lib version RoboCore)" "Plastal-Bot Builders" "https://github.com/Plastal-Bot-Builders/robocore-ide/tree/main/firmware/RoboCore"
} > "$OUT/THIRD-PARTY-NOTICES.txt"
echo "wrote $OUT"
