#!/usr/bin/env python3
"""Generate lib/data/robocore_v2_examples.dart from firmware/RoboCore/examples.

The RoboCore V2 examples in the IDE are the library's own example sketches, so the
app and the library cannot drift apart. CI compiles every one of them for the ESP32-S3.

    python3 tools/gen_examples.py           # write the Dart file
    python3 tools/gen_examples.py --check   # CI: fail if the Dart file is out of date
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / "firmware/RoboCore/examples"
DART = ROOT / "lib/data/robocore_v2_examples.dart"


def generate() -> str:
    sketches = sorted(d for d in EXAMPLES.iterdir() if d.is_dir())
    if not sketches:
        sys.exit(f"no examples found in {EXAMPLES}")
    out = [
        "// GENERATED from firmware/RoboCore/examples by tools/gen_examples.py.",
        "// Do not edit: change the example sketch and run `python3 tools/gen_examples.py`.",
        "",
        "/// RoboCore V2 example sketches, by folder name (the .ino inside it).",
        "const Map<String, String> kV2ExampleCode = {",
    ]
    for d in sketches:
        ino = d / f"{d.name}.ino"
        if not ino.exists():
            sys.exit(f"{ino.relative_to(ROOT)} is missing")
        code = ino.read_text(encoding="utf-8").replace("\r\n", "\n")
        if "'''" in code:
            sys.exit(f"{ino.relative_to(ROOT)} contains ''' which a Dart raw string cannot hold")
        if not code.endswith("\n"):
            code += "\n"
        out.append(f"  '{d.name}': r'''{code}''',")
    out += ["};", ""]
    return "\n".join(out)


def main() -> None:
    text = generate()
    if "--check" in sys.argv:
        current = DART.read_text(encoding="utf-8") if DART.exists() else ""
        if current != text:
            sys.exit(f"{DART.relative_to(ROOT)} is out of date: run python3 tools/gen_examples.py")
        print("examples match")
        return
    DART.write_text(text, encoding="utf-8")
    print(f"wrote {DART.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
