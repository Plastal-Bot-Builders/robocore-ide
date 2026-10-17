# RoboCore V2 support

Real RoboCore V2 (schematic Rev 2.0) support in the IDE, following the 10-step plan:

| # | Step | Where | Status |
|---|---|---|---|
| 1 | Pin map from the schematic | `hardware/pinout.md`, `firmware/RoboCore/src/RoboCoreV2Pins.h`, `lib/data/robocore_v2_pins.dart` | Done. Every GPIO checked against the Rev 2.0 schematic (U201 net labels and GPIO map) |
| 2 | RoboCore Arduino library | `firmware/RoboCore` | Done. PC checks pass (`-Werror`, logic tests) |
| 3 | Board test and examples | `firmware/RoboCore/examples` (BoardTest + 15) | Done. The IDE's V2 examples are generated from these (`tools/gen_examples.py`) |
| 4 | CI compile for the ESP32-S3 | `.github/workflows/firmware.yml` | Ready, first real run on this PR |
| 5 | Compile server (arduino-cli, Docker) | `server/`, `render.yaml` | Unit tests pass (12). Docker build and end-to-end smoke test run in CI |
| 6 | USB-C Connect and Serial Monitor (Web Serial) | `web/robocore_usb.js`, `lib/hw/usb_link*.dart`, Board Setup, Serial Monitor | Done. Plug-in / unplug notices, auto-reconnect, reconnect at start-up, Reset board |
| 7 | Upload with esptool-js | `lib/state/app_state.dart` (`_buildOnServer`, `_flash`), `web/vendor/esptool-js` (0.6.1) | Done. Problems tab, progress, hard reset, Serial Monitor reopens, BOOT + RESET tip |
| 8 | C++ labelling | Editor, new-project dialog, examples, projects, status bar, `.gitattributes` | Done |
| 9 | Four safety-check fixes | see below | Done |
| 10 | Pages fix | `build.yml` *Publish web app* | Done in CI; one repository setting needed (below) |

## How the pieces fit

```
 Blocks / C++  ──►  Verify ──► compile server (POST /compile) ──► problems + sizes
                    Upload ──► compile server ──► image.parts ──► esptool-js over Web Serial
                                                                   (closes the Serial Monitor reader,
                                                                    bootloader, write, hard reset,
                                                                    reopens the Serial Monitor)
 No compile server: Verify = built-in preview check. Port = preview board: Upload runs the simulator.
```

- **Port** (Board Setup, board menu, Serial Monitor): *Preview board (simulator)* or *USB-C board*. The choice is saved;
  on the next start the IDE reopens a board the browser already allowed, without asking.
- **Settings → Compile server**: the server's address and a **Test** button (`GET /health`).
- **Problems**: compiler errors and warnings from arduino-cli, with file, line and column. Errors inside a library name the library file.
- **Board pins in blocks**: on the V2 the *set pin* block offers only the free pins (IO3, IO37, IO43, IO44 and the servo pins),
  the *tone* block defaults to the buzzer (IO47), and the USER block reads IO42 without the internal pull-up.
- **Preview board on the V2**: `LED_BUILTIN` lights the RGB LED white (there is no plain LED), USER is IO42, `RC_PIN_…`
  names and `RoboCore::` helpers work, and `imu.begin()` reports success.

## The four safety-check fixes

1. **One damaged project no longer drops all projects.** Saved data is read one project (and one setting) at a time.
   Anything unreadable is kept under a `robocore-ide-v1-damaged-…` or `…-unreadable-…` key on the device, never deleted,
   and a notice says so.
2. **Flutter is pinned** (`FLUTTER_VERSION: 3.47.7` in `build.yml`), so a new Flutter release can't change a build by surprise.
3. **Every third-party action is pinned to a commit SHA** (with the version in a comment), in both workflows.
4. **Interpreter recursion depth is limited** (200 nested calls). Runaway recursion stops the preview with
   “stack overflow … A function that calls itself needs a way to stop” instead of exhausting memory.

## Publish web app (GitHub Pages)

The job failed with `Failed to create deployment (status: 404) … Ensure GitHub Pages has been enabled`: Pages was never
switched on for this repository (it moved from a personal account). That is a repository setting, not code:

**Settings → Pages → Build and deployment → Source: GitHub Actions** (once, by an admin).

The workflow now checks first: if Pages is off or publishes from a branch, the job ends with a warning that says exactly
this instead of failing the run. The actions were also updated (upload-pages-artifact v5, deploy-pages v5).

## What still needs the real board

Everything above is tested without hardware (C++ on a PC, the USB bridge against a fake Web Serial and esptool,
the app against a fake board and a mock compile server). These need the PCB:

- Which way each motor turns, encoder direction, line sensor polarity, sonar at 3.3 V (checklist below).
- The first real upload: esptool-js on the ESP32-S3's USB Serial/JTAG, the hard reset, and the Serial Monitor reopening.

## Test checklist on the real board

Arduino IDE 2 first (settings in `firmware/RoboCore/README.md`), then the same through RoboCore IDE once Upload works.

| # | Sketch | Expect |
|---|---|---|
| 1 | `BoardTest` | Part 1 all PASS/CHECK ok; part 2 (wheels lifted, switch ON) both motors spin both ways with encoder counts |
| 2 | `Blink` | RGB LED blinks white once a second; "RoboCore V2 ready" in the Serial Monitor |
| 3 | `ButtonLed` | LED on only while USER is held |
| 4 | `MotorControl` | Robot goes **forward**, back, turns. If a wheel goes the wrong way, note which one |
| 5 | `UltrasonicDistance` | Distance matches a ruler within about 1 cm from 5 to 150 cm |
| 6 | `LineFollower` | `line=` goes negative with the line under the left sensor, positive under the right |
| 7 | `SensorsToSerial` | `tilt_deg` about 0 flat, about 90 on its side; temperature sensible |
| 8 | `BuzzerTones`, `BuzzerMelody` | Notes play |
| 9 | `RgbColours` | Red, green, blue, amber |
| 10 | `ServoSweep` | Servo on port 1 sweeps |
| 11 | `ObstacleAvoider` | Drives forward, turns away from a wall at about 20 cm |
| 12 | `SerialEcho` | Replies; `led on` / `led off` work |

Report back for 4 and 6: if the defaults are wrong, change `_revR` / `_encRev*` in `RoboCoreMotors.h`
or `_darkHigh` in `RoboCoreSensors.h`, and the examples stay the same.
