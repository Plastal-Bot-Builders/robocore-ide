# Figma components vs the app

A review of every component on page **02 — Components** of the RoboCore IDE design
([Figma](https://www.figma.com/design/P7i2WBM8G96B2fTPHpp8yi), 13 families, about 80 components) against the web app
on branch `blockly-monaco-poc` (head 9f100ca), done on 21 October 2026. Each component was compared with the Figma
render and with the running app (headless Chrome, 1440 × 813) or, where noted, with the code. The Figma tool limit
(Starter plan) stopped the screenshot of the **Blockly** family, so that family was checked against the design's plugin
source (`RoboCore_IDE_Design/figma-plugin/src/04c_blockly.js`), as it was for this morning's Blockly fixes.

`docs/design-coverage.md` counts *behaviour* (does it work); this review is about *looks*: colour, layout, states.

## Summary

Counted by table row below (a row can cover a group, for example the nine select menus):

| Verdict | Rows |
|---|---|
| ✓ Matches the design | 29 |
| ≈ Small differences (wording, an icon, spacing) | 12 |
| ✗ Clear differences (looks wrong next to the design) | 15 |
| – Not checked this time | 3 (Cog answer cards, inline field editor, find widget) |
| n/a Not used by any screen | 1 (Checkbox) |

The differences that show most, in a suggested order of fixing:

1. **Green and red.** The design has no green or red: *connected* and *success* are navy (`color/ink/default`),
   errors are shown by contrast (navy bar, inverted toast), busy is the box yellow. The app uses green dots
   (Ready, Preview, Connected, the Serial Monitor dot), red error text and red buttons (Reset…, Delete project) —
   about 35 places (`c.ok`, `c.err` in `lib/ui`).
2. **Verify and Upload while busy.** The design shows *Verifying…* with a spinner and *Uploading 64 %* with a yellow
   progress bar inside the button; the app just greys both buttons out.
3. **Select menus.** The design marks the chosen option with a yellow row and a check, and the select itself gets an
   ink border and an up chevron while open; the app only bolds the option. Same for the board selector.
4. **Output panel.** Errors should be an inverted navy line with a yellow *Explain* chip on it, not red text under a
   separate *Explain with Cog* bar; the log should start at the top, not the bottom; the empty Output and Problems
   messages are worded and placed differently.
5. **Toasts.** The design has three: success and info (white card, icon, bold title, message, close) and error (navy).
   The app shows every toast as one navy line.
6. **Blocks.** Empty yes/no slots are solid navy instead of a darker tint of the block; *repeat 5 times* has an extra
   *do*; *if … then* breaks *then* onto a second row; *repeat until* has an *until ▾* menu and *do*; Blockly's dropdown
   menus are drawn in the block colour instead of the white menu with a yellow selected row.
7. **Top bar order** in the editor: the design has Board · Verify · Upload · (Stop) · Ask Cog · ⚙ · avatar; the app
   puts Ask Cog before Verify.
8. **Choice cards** (How should Cog help?, Appearance): the radio is on the right in the design, on the left in the app.

## Family by family

✓ matches · ≈ small difference · ✗ clear difference · – not checked

### Logo & icons

| Component | | Notes |
|---|---|---|
| Logo components | ✓ | Geared Ring mark and lockup in the top bar. |
| Icon set (Lucide, 20 px) | ✓ | |

### Actions

| Component | | Notes |
|---|---|---|
| Button (Primary, Secondary, Ghost × states) | ≈ | Matches, but the app also has a red outlined button (Reset…, Delete project) that is not a design variant. |
| Icon Button | ✓ | Default, hover, active (yellow tint), disabled, tooltip. |
| Toolbar Action | ✗ | No running states: *Verifying…* (spinner) and *Uploading 64 %* (spinner, yellow progress bar along the bottom). Stop matches (navy square, only while something runs). |

### Navigation

| Component | | Notes |
|---|---|---|
| Nav Item | ≈ | Matches, expanded and collapsed. The Serial Monitor dot is green (design navy). **Bug:** the sidebar's collapse animation overflows a nav row (`RenderFlex overflowed`, `lib/ui/shell.dart:803`). |
| Mode Switch | ✓ | Blocks · Code since this morning. |
| File Tab | ✓ | |
| Panel Tab | ✓ | Count badge on Problems. (The design keeps the trash button on the Problems tab; the app hides it there.) |

### Hardware

| Component | | Notes |
|---|---|---|
| Badge | ✓ | Neutral, Brand, Ink. |
| Connection Status | ✗ | Connected is a green dot (design navy). The app's status has no *Uploading…* (yellow dot) or *Port unavailable* (warning icon) state; the status bar has the yellow busy dot. |
| Board Selector | ✗ | No open state (ink border, up chevron) while its menu is open; green dot. |
| Board Info Card | ≈ | Green dot; an empty port reads "—" (design "None selected"). |
| Board Menu | ✓ | Chip icons, check on the chosen board, port select, Board setup →. (Green dot.) |

### Forms & feedback

| Component | | Notes |
|---|---|---|
| Input Field | ✗ | Error state is a red border and red text; the design keeps an ink border, puts a warning icon inside the field and writes the message in bold ink. Default, focus, disabled and helper text match. |
| Search Field | ✓ | |
| Select | ✗ | No open state (ink border, up chevron). |
| Select menus (Baud, Port, Board, Line ending, Font size, Language, Level, CPU, Partition) | ✗ | Chosen option is only bold; design: yellow row, bold text, check on the right. Port's USB option reads "USB-C board…" (design "USB-C · ESP32-S3 (usbmodem1101)"); Font size adds 15 and 18 px (design 12, 13, 14, 16). |
| Menu Item | ✓ | In the account, project and board menus. |
| Toggle | ✓ | |
| Checkbox | n/a | No screen uses one. |
| Radio | ✓ | |
| Tooltip | ≈ | Shortcuts are written "Verify (Cmd+R)"; the design shows the shortcut faint after the label. |
| Avatar | ✓ | |
| Toast | ✗ | One navy line for everything; the design has success / error / info toasts with icon, title, message and close. |
| Mode Choice | ✓ | (C++ option reads "Arduino-style C++ code", design "Arduino C++".) |
| Help Style | ✗ | Radio on the left (design right). The descriptions differ; the app's describe what Cog really does (fix after two hints). |
| Theme Choice | ✗ | Radio on the left plus a colour swatch; design: radio right, "Light · the box colours" / "Dark · the box, inverted". |
| Library Action | ✗ | Install has no download icon; *Installed* is a grey badge that turns into an underlined "Remove" link on hover; the design has ✓ Installed (ghost) → Remove (outlined, trash icon) and *Installing…* with a spinner. |
| Server Test | ≈ | Test has no plug icon. |

### Blocks

| Component | | Notes |
|---|---|---|
| Block Category | ✓ | Fixed this morning (34 px rows, 22 px chips, selected row). |
| Block library | ✗ | Mostly matches; four differences: empty yes/no slots are solid navy (design: darker tint of the block colour); *repeat 5 times* adds *do*; *if ◇ then* puts *then* on a second row (and the gear, now navy); *repeat until* has an *until ▾* menu and *do*. The *define* block of My Blocks was not checked. Variables shows only "Make a variable…" until a variable exists (Blockly's behaviour; the design shows the blocks). |

### Cog — learning partner

| Component | | Notes |
|---|---|---|
| Cog Button | ✓ | Outline, navy when open. |
| Chat Message | ✓ | |
| Context Chip | ✓ | |
| Prompt Chip | ✓ | |
| Cog Composer | ✗ | Send is an arrow outside the field; the design has a paper-plane icon inside it. |
| Cog Header | ≈ | Extra "+" (new conversation) not in the design. |
| Explain Lens | ✓ | |
| Hint Card, Suggestion, Quick Check, Concepts, Cog Offline | – | Need a Cog answer (stand-in API) to show; not re-checked today. |

### App chrome

| Component | | Notes |
|---|---|---|
| Sidebar Project | ✓ | |
| Sidebar | ✓ | (Green dot; collapse overflow bug above.) |
| Top Bar | ✗ | Editor: Ask Cog sits before Verify; design order is Board · Verify · Upload · (Stop) · Ask Cog · ⚙ · avatar. Home bar matches. |
| Status Bar | ≈ | Green dot. |

### Cards & dialogs

| Component | | Notes |
|---|---|---|
| Project Card | ✓ | Fixed this morning. |
| Example Card | ≈ | Description wraps to two lines (design one line, truncated). |
| Template Tile | ✓ | |
| Dialog/New Project | ≈ | No divider above the buttons. |
| Dialog/Project Settings | ≈ | *Delete project* is red (design: ink, ghost, trash icon); Cancel is a ghost button (design outlined); no dividers above Auto-save and the buttons. |

### Blockly (checked against the plugin source)

| Component | | Notes |
|---|---|---|
| Blockly Palette | ✓ | Fixed this morning (toolbox, flyout title, 288 px flyout, fixed size when zooming). |
| Blockly Zoom | ✓ | |
| Blockly Trashcan | ✓ | |
| Dropdown under a field | ✗ | Drawn in the block's colour with a tick on the left; the design uses the white menu (yellow selected row, check on the right, small white arrow). |
| Context menus | ✓ | Close enough (white, Barlow, shortcuts). |
| Inline field editor | – | Not checked. |

### Monaco

| Component | | Notes |
|---|---|---|
| Code Banner | ✓ | Generated / Edited (with Rebuild from blocks) / C++ project. |
| Find Widget | – | Not checked. |

### Panels

| Component | | Notes |
|---|---|---|
| Console Panel | ✗ | Errors: red text plus a separate *Explain with Cog* bar (design: inverted navy line with an inline yellow *Explain* chip; *Compilation failed* in the brand ochre). The log is bottom-aligned (design top). Empty Output reads "Verify or upload to see build output here." centred (design "Messages from Verify and Upload appear here." top-left in the log font, or "Upload runs the sketch on the preview board."). Empty Problems reads "No problems found. Press Verify…" centred (design "✓ No problems in this sketch." top-left). Problem rows use a red alert icon (design ink warning triangle). Serial empty state: "No board connected" in sentence case (design NO BOARD CONNECTED) and a chip icon on Connect (design plug). |
| Cog Panel | ≈ | See Cog above. |
| Preview Board | ≈ | USER is filled navy when up (design outlined; filled only while held). A white LED shows as a white ring that looks off; the design shows a lit LED in the box yellow. |

## Not in the design (yours to decide)

- **Zoom buttons and % in the blocks toolbar.** The design's blocks header has only Undo, Redo, Clear; zoom is the
  canvas buttons, which now match the design. Added with the zoom work on 20 October.
- **"C++ from the blocks" pane** beside the blocks (and its toggle). The design shows the C++ only in Code mode.
- **"+" new conversation** in the Cog header, and **Explain** on Problems rows.
- **Red Reset… and Delete project buttons** (see Actions).

## Bugs found while reviewing

- Sidebar collapse animation: `A RenderFlex overflowed by 23 pixels` from the nav row at `lib/ui/shell.dart:803`
  while the sidebar is narrower than its content.
