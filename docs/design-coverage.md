# Design coverage

How much of the RoboCore IDE design ([Figma](https://www.figma.com/design/P7i2WBM8G96B2fTPHpp8yi), its behaviour spec and
block catalogue in `RoboCore_IDE_Design/docs/`) the app does. Each spec row is one test case; **Done** = 1, **Partly**
= ½, **Missing** = 0. Checked against the code and the running web app on branch `blockly-monaco-poc`. Update a row
when you finish it.

This counts behaviour. How each component *looks* next to the Figma Components page is in
[component-review.md](component-review.md).

## Score

| Part | Done | Partly | Missing | Score | At the first audit (20 Oct) |
|---|---|---|---|---|---|
| Behaviour spec (145 rows) | 145 | 0 | 0 | **145 / 145 = 100 %** | 117 / 145 = 81 % |
| Block catalogue (74 blocks, 10 categories) | 74 | | 0 | **74 / 74 = 100 %** | 25 / 74 = 34 % |
| Both together | | | | **219 / 219 = 100 %** | 65 % |

Not counted: things only real hardware can prove, and Cog with a real Claude key (tested only against a stand-in
API). On a RoboCore V2 (arriving about 11 November) still to try: upload, cancelling an upload, Test connection, reset
and unplug, all tested so far against a stand-in board and flasher; and how far the robot really moves and turns.

## Behaviour spec, row by row

### G — Everywhere (17 / 17)

| ID | Status | Note |
|---|---|---|
| G-01 Logo → Home | Done | |
| G-02 Sidebar items | Done | |
| G-03 Open project | Done | |
| G-04 Collapse sidebar | Done | Also Ctrl/⌘+B, from inside the editors too |
| G-05 Board selector | Done | Esc closes it |
| G-06 Pick a board | Done | |
| G-07 Preview board | Done | |
| G-08 USB-C | Done | |
| G-09 Settings icon | Done | |
| G-10 Account menu | Done | |
| G-11 Search | Done | Projects, Examples and Help (pages and dialogs, found by name or a word like “baud”); Esc works |
| G-12 New project | Done | |
| G-13 Status bar · board → Board Setup | Done | |
| G-14 Tooltips with shortcut | Done | Verify (Ctrl/⌘+R), Upload (Ctrl/⌘+U), Ask Cog, zoom |
| G-15 Esc closes the top-most thing | Done | Every menu, the search and every dialog |
| G-16 Toasts | Done | Bottom right; 4 s; errors stay with a close button |
| G-17 Hover states | Done | |

### W — First start (4 / 4)

| ID | Status | Note |
|---|---|---|
| W-01 Welcome first | Done | |
| W-02 Name rules | Done | |
| W-03 School shown | Done | Home (“ROBOCORE V2 · GRADE 7B”) and the account menu |
| W-04 Get started | Done | |

### H — Home (7 / 7)

| ID | Status | Note |
|---|---|---|
| H-01 … H-07 | Done | Recent cards have the ⋮ menu |

### PR — Projects (10 / 10)

| ID | Status | Note |
|---|---|---|
| PR-01 Filter chips + count | Done | “n of m projects” |
| PR-02, PR-03, PR-10 | Done | |
| PR-04 Card ⋮ menu | Done | Open, Rename…, Duplicate, Download, Delete… |
| PR-05 Rename… | Done | Name selected; required and unique; Enter saves |
| PR-06 Duplicate | Done | “… copy” at the top, toast |
| PR-07 Download .ino / .zip | Done | Browser download; a sketch folder .zip with more tabs; native apps copy the code |
| PR-08 Delete… with confirm | Done | “Delete Blink LED?” dialog, also from Project settings |
| PR-09 Empty state | Done | Robot art, New project, Browse examples |

The page also has its **New project** button, as in Figma.

### EX — Examples (4 / 4)

| ID | Status | Note |
|---|---|---|
| EX-01 … EX-04 | Done | A card opens the preview; Open as new project copies it |

### L — Libraries (4 / 4)

| ID | Status | Note |
|---|---|---|
| L-01 … L-04 | Done | “NewPing is not installed. Install it in Libraries.”, also before a compile on the server |

### B — Board Setup (10 / 10)

| ID | Status | Note |
|---|---|---|
| B-01 … B-03, B-05 … B-10 | Done | Upload/reset/unplug still to try on a real board |
| B-04 Test connection | Done | On USB-C asks the chip its name through its bootloader (“Board answered · ESP32-S3 (QFN56) (revision v0.2)”), warns if it is a different chip; the board restarts |

### SM — Serial Monitor (7 / 7)

| ID | Status | Note |
|---|---|---|
| SM-01 … SM-06 | Done | |
| SM-07 No board | Done | Empty state with Connect; with earlier lines in the log, a bar with Connect above them |

### ST — Settings (12 / 12)

| ID | Status | Note |
|---|---|---|
| ST-01 … ST-11 | Done | Explanation level is sent to Cog with every request |
| ST-12 Reset all data | Done | Confirm dialog, then Welcome; the next profile gets the starter projects |

Laid out in two columns on wide windows, as in Figma.

### E — Editor header and build (13 / 13)

| ID | Status | Note |
|---|---|---|
| E-01 … E-06, E-08 … E-13 | Done | The project name opens Rename…, Project settings…, Duplicate, Download, Delete project… |
| E-07 Stop | Done | In the top bar only while Verify, Upload or the preview sketch runs. Cancels compiling at once; while flashing, the flasher stops at its next block and restarts the board (says if the program is now incomplete) |

### BK — Blocks (23 / 23)

| ID | Status | Note |
|---|---|---|
| BK-01 … BK-08, BK-11 … BK-15, BK-17 | Done | Blockly |
| BK-09 Undo / Redo | Done | Greyed out when Blockly has nothing to undo or redo |
| BK-10 Delete all | Done | “Delete all 6 blocks?” dialog; Undo brings them back |
| BK-16 Selection + keyboard | Done | Yellow outline (navy on the yellow Events blocks, cream in the dark theme); Blockly 13's keyboard navigation: arrows move, Enter edits a field, T opens the toolbox (in the shortcuts dialog) |
| BK-18 Ten categories | Done | Hardware first, round coloured icons, as in Figma |
| BK-19 Robot blocks | Done | move / turn / start / steer / stop, speed, wheel size, distance moved (RoboCoreDrive) |
| BK-20 “When …” hats | Done | Checked at the top of loop() (phase 1 in the spec) |
| BK-21 Sensor questions | Done | A value and a yes / no block for each sensor |
| BK-22 Make a block | Done | My Blocks: Make a block… → define + call (a C++ function; parameters are float) |
| BK-23 Library helpers | Done | All 31 are in the RoboCore library; host-tested and compiled for the ESP32-S3 |

### CD — Code (12 / 12)

| ID | Status | Note |
|---|---|---|
| CD-01 Banner | Done | Generated / You edited this file (Rebuild from blocks) / C++ project |
| CD-02 Rebuild from blocks | Done | Asks first |
| CD-03 File tabs | Done | **+** adds a .ino, .h, .hpp, .c or .cpp tab |
| CD-04 Suggestions | Done | Arduino + RoboCore API with a line of docs each (lib/data/arduino_api.dart) |
| CD-05 Parameter hints | Done | The argument you are typing is bold |
| CD-06 Hover | Done | Signature, doc and the Arduino reference link (each link checked) |
| CD-07, CD-09 … CD-12 | Done | |
| CD-08 Quick fix | Done | “Change spelling to 'digitalWrite'” from the compiler, and Explain with Cog |

### C — Console (6 / 6)

| ID | Status | Note |
|---|---|---|
| C-01 … C-06 | Done | Ctrl/⌘+J collapses the console; remembered on this device |

### PB — Preview board (5 / 5)

| ID | Status | Note |
|---|---|---|
| PB-02 … PB-05 | Done | |
| PB-01 Live parts | Done | LED, RGB, USER, motors, servo, buzzer; sonar, line, tilt and battery update live, and a click holds any of them at a value (slider, Auto to let go) |

### CG — Cog (8 / 8), D — Dialogs (3 / 3)

All done. Cog is tested against a stand-in API only.

## Block catalogue

All 74 blocks are in the toolbox, in the 10 categories, with the catalogue's words and C++. A workspace holding every
block generates a sketch that compiles for the RoboCore V2 (real ESP32-S3 compiler) and runs in the preview board
(test/fixtures/all_blocks.ino). Small differences from the catalogue:

- **set pin / read pin** write the pin number (`digitalWrite(37, HIGH)`), the same pin as `RC_PIN_EXP_IO37`; the menu
  shows IO37.
- **print** takes any value or text (a value slot with “RoboCore V2 ready” in it).
- **Pins & Serial** is always shown (the catalogue shows it from the Intermediate level).
- **when &lt;condition&gt;** writes `when1.rose(condition)` (a `RoboCoreEdge`), not `becameTrue(condition)`.
- Projects from the first block set still open: blocks with the same meaning show the new words, the others
  (drive at %, stop motors, tone pin, print distance) still work but are no longer in the toolbox.

To check on the first robot: encoder counts per wheel turn (292.5 assumed for XRP motors), the IMU's yaw direction,
and how far move and turn really go.
