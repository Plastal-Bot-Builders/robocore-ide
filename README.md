# RoboCore IDE (Flutter)

One codebase for the RoboCore IDE on **web, Android, iPhone/iPad, Windows and macOS**, built from the Plastal-bot Builders Figma design.

## What's in it

- **Home, Projects, Examples, Libraries, Board Setup, Serial Monitor, Settings**: every screen from the Figma file, in the Paper (cream) and Navy themes.
- **Blocks editor**: drag blocks from the palette, reorder them, drop them on the palette to delete, undo and redo, and zoom. Blocks generate Arduino code.
- **Code editor**: syntax highlighting, line numbers, find, auto-indent, Arduino autocomplete and multiple files.
- **Verify and Upload**: checks the sketch like the Arduino compiler (missing includes, undeclared names, types and board support), then runs it on a **simulated RoboCore board** (LED, RGB LED, USER button, motors, servo, sonar, line sensor, IMU and serial in and out).
- Projects and settings are saved on the device.

## Run it

You need the Flutter SDK (stable channel).

```bash
# first time only: generate the platform folders
flutter create --platforms=web,android,ios,windows,macos --project-name robocore_ide --org com.robocore .

flutter pub get
flutter run -d chrome      # web
flutter run -d windows     # or macos, or an Android / iOS device
flutter test               # compiles and runs every example sketch
```

## Automatic builds

Every push to `main` runs `.github/workflows/build.yml`. It analyzes and tests the code, then builds:

| Platform | Output |
| --- | --- |
| Web | Published to GitHub Pages (Settings → Pages → Source: **GitHub Actions**) |
| Android | `app-release.apk` (download it from the workflow run's artifacts) |
| Windows | `robocore-ide-windows` folder (artifact) |
| macOS | `robocore-ide-macos.zip` (artifact) |
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

## Next: the real RoboCore PCB

Talking to the real board will plug in behind the simulated board (`lib/state/sim_board.dart` implements `BoardIO`):

- **Serial**: Web Serial on web, USB serial on Android and desktop, and Bluetooth LE on iPhone/iPad (iOS doesn't allow USB serial).
- **Upload**: a small compile server running `arduino-cli`, then flashing over USB.

These need the board's schematic, chip, USB details and pin map.
