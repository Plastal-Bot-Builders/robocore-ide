#!/usr/bin/env bash
# Host checks for the RoboCore library (no ESP32 compiler needed):
#  1. every library source and example passes g++ -Wall -Wextra -Werror against stand-in Arduino headers
#  2. the library's logic (motor direction, encoders, sonar, line, IMU, battery) passes library_test.cpp
# The real ESP32-S3 compile runs in .github/workflows/firmware.yml.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lib="$here/../../RoboCore/src"
ex="$here/../../RoboCore/examples"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
flags=(-std=gnu++2b -Wall -Wextra -Werror -I"$here" -I"$lib")

for f in "$lib"/*.cpp; do
  g++ "${flags[@]}" -fsyntax-only "$f"
  echo "ok  $(basename "$f")"
done
for d in "$ex"/*/; do
  n="$(basename "$d")"
  { echo '#include "Arduino.h"'; cat "$d/$n.ino"; } > "$out/$n.cpp"
  g++ "${flags[@]}" -fsyntax-only "$out/$n.cpp"
  echo "ok  examples/$n"
done
g++ -std=gnu++2b -I"$here" -I"$lib" "$here/library_test.cpp" "$lib"/*.cpp -o "$out/library_test"
"$out/library_test"
