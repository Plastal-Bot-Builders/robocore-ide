# Design coverage

How much of the RoboCore IDE design ([Figma](https://www.figma.com/design/P7i2WBM8G96B2fTPHpp8yi), its behaviour spec and
block catalogue in `RoboCore_IDE_Design/docs/`) the app does. Each spec row is one test case; **Done** = 1, **Partly**
= ½, **Missing** = 0. Checked against the code and the running web app on branch `blockly-monaco-poc`. Update a row
when you finish it.

## Score

| Part | Done | Partly | Missing | Score | At the first audit (20 Oct) |
|---|---|---|---|---|---|
| Behaviour spec (145 rows) | 133 | 7 | 5 | **136.5 / 145 = 94 %** | 117 / 145 = 81 % |
| Block catalogue (74 blocks, 10 categories) | 25 (old wording, old categories) | | 49 | **25 / 74 = 34 %** | 34 % |
| Both together | | | | **161.5 / 219 = 74 %** | 65 % |

Not counted: things only real hardware can prove (upload, reset and unplug on a RoboCore V2, which arrives about
11 November) and Cog with a real Claude key (tested only against a stand-in API).

## Behaviour spec, row by row

### G — Everywhere (16.5 / 17)

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
| G-11 Search | Partly | No **Help** group (there are no help pages yet); Esc works |
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

### B — Board Setup (9.5 / 10)

| ID | Status | Note |
|---|---|---|
| B-01 … B-03, B-05 … B-10 | Done | Upload/reset/unplug still to try on a real board |
| B-04 Test connection | Partly | Doesn't ask the chip its name |

### SM — Serial Monitor (6.5 / 7)

| ID | Status | Note |
|---|---|---|
| SM-01 … SM-06 | Done | |
| SM-07 No board | Partly | Connect button, no empty state |

### ST — Settings (12 / 12)

| ID | Status | Note |
|---|---|---|
| ST-01 … ST-11 | Done | Explanation level is sent to Cog with every request |
| ST-12 Reset all data | Done | Confirm dialog, then Welcome; the next profile gets the starter projects |

Laid out in two columns on wide windows, as in Figma.

### E — Editor header and build (12.5 / 13)

| ID | Status | Note |
|---|---|---|
| E-01 … E-06, E-08 … E-13 | Done | The project name opens Rename…, Project settings…, Duplicate, Download, Delete project… |
| E-07 Stop | Partly | Stops the simulator; can't cancel an upload |

### BK — Blocks (17 / 23)

| ID | Status | Note |
|---|---|---|
| BK-01 … BK-08, BK-11 … BK-15, BK-17 | Done | Blockly |
| BK-09 Undo / Redo | Done | Greyed out when Blockly has nothing to undo or redo |
| BK-10 Delete all | Done | “Delete all 6 blocks?” dialog; Undo brings them back |
| BK-16 Selection + keyboard | Partly | Keyboard navigation not checked |
| BK-18 Ten categories | Missing | Still the old 8 |
| BK-19 Robot blocks | Missing | |
| BK-20 “When …” hats | Missing | |
| BK-21 Sensor questions | Partly | Only “USER pressed?” |
| BK-22 Make a block | Missing | |
| BK-23 Library helpers | Missing | 31 helpers to add to the RoboCore library |

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

### PB — Preview board (4.5 / 5)

| ID | Status | Note |
|---|---|---|
| PB-02 … PB-05 | Done | |
| PB-01 Live parts | Partly | LED, RGB, motors, servo, buzzer; sonar, line, tilt and battery can't be set |

### CG — Cog (8 / 8), D — Dialogs (3 / 3)

All done. Cog is tested against a stand-in API only.

## Block catalogue

25 of the 74 blocks exist, most with the old wording (“set built-in LED to HIGH” for “turn LED on”), in the old 8
categories. Missing: every “when …” hat and broadcast, the robot blocks (move / turn / steer / speed / wheel size),
per-wheel motors and servos, LED brightness, melodies, start / stop sound, most sensor questions and values (tilt,
yaw, battery, temperature, timer), wait until, stop program, between / round / join, My Blocks, read pin, read analog
pin and serial read line. 31 of the blocks need a new helper in the RoboCore library first.
