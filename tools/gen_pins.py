#!/usr/bin/env python3
"""Generate lib/data/robocore_v2_pins.dart from firmware/RoboCore/src/RoboCoreV2Pins.h.

The C++ header is the single source of truth for the RoboCore V2 pin map.

    python3 tools/gen_pins.py           # write the Dart file
    python3 tools/gen_pins.py --check   # CI: fail if the Dart file is out of date
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HEADER = ROOT / "firmware/RoboCore/src/RoboCoreV2Pins.h"
DART = ROOT / "lib/data/robocore_v2_pins.dart"

SCALAR = re.compile(r"^constexpr\s+(uint8_t|float)\s+(RC_[A-Z0-9_]+)\s*=\s*([^;]+);")
ARRAY = re.compile(r"^constexpr\s+uint8_t\s+(RC_[A-Z0-9_]+)\[\]\s*=\s*\{([^}]*)\};")


def camel(name: str) -> str:
    parts = name.removeprefix("RC_").removeprefix("PIN_").lower().split("_")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def number(text: str, kind: str) -> str:
    text = text.strip()
    if kind == "float":
        return str(float(text.rstrip("fF")))
    return str(int(text, 0))


def generate() -> str:
    scalars, arrays = [], []
    for line in HEADER.read_text().splitlines():
        line = line.strip()
        if m := SCALAR.match(line):
            kind, name, value = m.groups()
            scalars.append((camel(name), number(value, kind), name))
        elif m := ARRAY.match(line):
            name, body = m.groups()
            values = [str(int(v, 0)) for v in body.split(",") if v.strip()]
            arrays.append((camel(name), values, name))
    if not scalars:
        sys.exit(f"no pins found in {HEADER}")
    names = [n for n, _, _ in scalars] + [n for n, _, _ in arrays]
    if len(names) != len(set(names)):
        sys.exit("two pins map to the same Dart name")
    out = [
        "// GENERATED from firmware/RoboCore/src/RoboCoreV2Pins.h by tools/gen_pins.py.",
        "// Do not edit: change the header and run `python3 tools/gen_pins.py`.",
        "",
        "/// RoboCore V2 (Rev 2.0) pin map, shared with the RoboCore Arduino library.",
        "class RoboCoreV2Pins {",
        "  RoboCoreV2Pins._();",
        "",
    ]
    for dart, value, c in scalars:
        out.append(f"  static const {dart} = {value}; // {c}")
    for dart, values, c in arrays:
        out.append(f"  static const {dart} = <int>[{', '.join(values)}]; // {c}")
    out += [
        "",
        "  /// The same values under their C++ names, for the IDE's sketch checker and simulator.",
        "  static const byCName = <String, num>{",
    ]
    for _, value, c in scalars:
        out.append(f"    '{c}': {value},")
    out += ["  };", "}", ""]
    return "\n".join(out)


def main() -> None:
    text = generate()
    if "--check" in sys.argv:
        current = DART.read_text() if DART.exists() else ""
        if current != text:
            sys.exit(f"{DART.relative_to(ROOT)} is out of date: run python3 tools/gen_pins.py")
        print("pins match")
        return
    DART.parent.mkdir(parents=True, exist_ok=True)
    DART.write_text(text)
    print(f"wrote {DART.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
