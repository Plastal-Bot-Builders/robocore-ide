# RoboCore IDE (Flutter)

One codebase for the RoboCore IDE on **web, Windows, macOS, Linux, Android and iPhone/iPad**, built from the Plastal-bot Builders Figma design.

## What's in it

- **Home, Projects, Examples, Libraries, Board Setup, Serial Monitor, Settings**: every screen from the Figma file, in the Paper (cream) and Navy themes.
- **Blocks editor**: Google Blockly in the web app (RoboCore blocks plus if / else, loops, comparisons and variables; C++ updates live beside the blocks), and the same page in a WebView in the macOS app. The other native apps keep a simpler Flutter block editor for now. Blocks generate Arduino C++ code. See `docs/blockly-monaco.md`.
- **C++ editor**: Monaco (the editor in VS Code) in the web app: C++ highlighting, Arduino and RoboCore suggestions and hovers, find, compile problems in the code, multiple files; also in the macOS app. The other native apps use a Flutter code editor.
- **Verify and Upload**: with a compile server, a real C++ build (arduino-cli) and an upload over USB-C to the RoboCore V2. Without one, a built-in check like the Arduino compiler's (missing includes, undeclared names, types and board support), then a run on a **simulated RoboCore board** (RGB LED, USER button, motors, servo, sonar, line sensor, IMU, battery and serial in and out).
- **Cog, the learning partner** (Ask Cog, Ctrl+I): explains errors and blocks, gives hints one at a time before it ever
  shows a fix, applies a fix only when the student presses Apply, asks a quick question afterwards, and keeps a "You've
  learned" list per project. It runs through the compile server, which holds the Anthropic API key. See `docs/cog.md`.
- Projects and settings are saved on the device.

## Run it

You need the Flutter SDK (stable channel, the version in `FLUTTER_VERSION` in `.github/workflows/build.yml`).
Desktop and phone builds also need that platform's tools: Xcode for macOS and iOS, Visual Studio (Desktop C++) for
Windows, `clang cmake ninja-build pkg-config libgtk-3-dev` for Linux, Android Studio for Android. `flutter doctor` lists what's missing.

```bash
flutter pub get
flutter run -d chrome      # web
flutter run -d macos       # or windows, linux, or an Android / iOS device
flutter test               # compiles and runs every example sketch
bash tools/package_rpm.sh  # builds an installable .rpm for Fedora / RPM Linux
```

The platform folders (`android/ ios/ macos/ windows/ linux/`) are committed: they hold the app name (RoboCore),
icons, window size and permissions (internet for the compile server; the macOS sandbox's outgoing-connections
entitlement). `python3 tools/gen_app_icons.py` (needs Node, Pillow and numpy) draws every platform's icon, the
"Geared Ring", from the master geometry in `tools/app_icon/` (a copy of the design in the Figma file
"RoboCore IDE — App Icon").

## Automatic builds

Every push to `main` runs `.github/workflows/build.yml`. It analyzes and tests the code, then builds:

| Platform | Output |
| --- | --- |
| Web | Published to GitHub Pages (Settings → Pages → Source: **GitHub Actions**) |
| Android | `app-release.apk` (download it from the workflow run's artifacts) |
| Windows | `robocore-ide-windows` folder with `RoboCore.exe` (artifact) |
| Linux | `robocore-ide-linux-x64.rpm` (Fedora / RPM) and `robocore-ide-linux-x64.tar.gz` (portable bundle) in the `robocore-ide-linux` artifact |
| macOS | `robocore-ide-macos.zip` with `RoboCore.app` (artifact). It isn't notarized: the first time, right-click it and choose **Open** |
| iOS | Unsigned `Runner.app` (artifact). Store or TestFlight builds need an Apple developer account and signing. |

## Project layout

```
lib/
  data/catalog.dart        boards, libraries, examples, block definitions
  engine/                  lexer, parser, compiler checks, interpreter, blocks → code
  state/                   app state, project models, simulated board
  ui/shell.dart            top bar, sidebar, status bar, board menu, search
  ui/pages/                Home, Projects, Examples, Libraries, Board, Serial, Settings
  ui/editor/               Blocks workspace, code editor, console, live board
assets/                    fonts (Barlow, Barlow Condensed, JetBrains Mono) and images
```

## The real RoboCore V2

The IDE talks to a real RoboCore V2 (schematic Rev 2.0, ESP32-S3-WROOM-1-N8R2) over USB-C.

| Part | Where |
| --- | --- |
| Pin map | `hardware/pinout.md`, from `hardware/RoboCore_V2_schematic_rev2.0.pdf`. In code: `firmware/RoboCore/src/RoboCoreV2Pins.h` (the single source of truth), generated into `lib/data/robocore_v2_pins.dart` by `tools/gen_pins.py` |
| Arduino library | `firmware/RoboCore`: `RoboCoreMotors`, `Sonar`, `LineSensor`, `IMU`, `RoboCore::` helpers, `RC_PIN_…` names |
| Board test and examples | `firmware/RoboCore/examples`. The IDE's RoboCore V2 examples are these files (`tools/gen_examples.py` writes `lib/data/robocore_v2_examples.dart`) |
| Compile server | `server/`: arduino-cli 1.5.1, esp32 core 3.3.12, Docker. Deploy with `render.yaml` or Cloud Run (`server/README.md`) |
| Connect and Serial Monitor | Web Serial in Chrome or Edge (`web/robocore_usb.js`): plug-in and unplug notices, automatic reconnect |
| Upload | The project goes to the compile server, then esptool-js (`web/vendor/esptool-js`) writes it over the same USB-C port, resets the board and reopens the Serial Monitor. An Arduino Uno gets the server's HEX through its Optiboot bootloader instead (STK500v1 in `web/robocore_usb.js`: written page by page, read back to check) |

To use it:

1. Run the compile server (`server/README.md`) and put its address in **Settings → Compile server**. Press **Test**.
2. Open the web app in Chrome or Edge, plug in the RoboCore, and in **Board Setup** pick **USB-C** and press **Connect**
   (the ESP32-S3 shows up as “USB JTAG/serial debug unit”).
3. **Upload** compiles and flashes. If the board doesn't answer, hold **BOOT**, tap **RESET**, release **BOOT**, and upload again.
   (An Arduino Uno needs no buttons: check that Board Setup is set to the Uno and that no other program, such as the
   Arduino IDE's Serial Monitor, has its port open.)

Without a board the IDE keeps using the **preview board** (the simulator), and without a compile server **Verify** uses the
built-in preview check. The macOS app uploads over USB too: the same USB helper runs in a hidden WebView on the Mac's
serial ports (`lib/hw/usb_link_native.dart`, `web/robocore_serial_shim.js`, `macos/Runner/SerialPorts.swift`), with the
app's own port chooser. The other native apps (Windows, Linux, Android, iOS) use the preview board for now.

`docs/robocore-v2-support.md` has the full status and the test checklist for the real board.

## Checks

| Workflow | What it runs |
| --- | --- |
| `build.yml` | USB bridge and editor shortcut tests (`node --test test/js/robocore_usb.test.mjs test/js/robocore_editors.test.mjs`), `dart analyze`, `flutter test`, and the web, Android, Windows, Linux, macOS and iOS builds. Flutter is pinned (`FLUTTER_VERSION`) and every action is pinned to a commit |
| `firmware.yml` | Pin map and examples in sync with the app, the library and examples on a PC (`-Werror` plus logic tests), a real ESP32-S3 compile of every example, the compile server's tests, and its Docker image compiling every example end to end |

**GitHub Pages:** the web app is published by the *Publish web app* job. It needs Pages switched on once:
**Settings → Pages → Build and deployment → Source: GitHub Actions**. Until then that job skips with a warning, and the
web build is still saved to the `web-build` branch.
