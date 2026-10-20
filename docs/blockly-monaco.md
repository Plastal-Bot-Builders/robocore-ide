# Blockly and Monaco (proof of concept)

The web app's editors are now **Google Blockly** (Blocks) and **Monaco** (C++), set up as in the design's
behaviour spec (*Handoff: Blockly* and *Handoff: Monaco*). The native apps keep the Flutter editors for now.

## How it fits together

```
EditorPage ──► BlocklyEditor / MonacoEditor        lib/ui/editor/web_editors_web.dart (web)
                   │  iframe                        lib/ui/editor/web_editors_stub.dart (native: not used)
                   ▼
           web/robocore_editors.html#blocks | #code
                   │  window.rcEditor
                   ▼
           web/robocore_editors.js ── Blockly 13.3 (web/vendor/blockly)
                                   └─ Monaco 0.57   (web/vendor/monaco)
```

- Each editor runs in its own page inside an iframe, so its scripts, styles and keyboard shortcuts stay apart from
  Flutter's (Flutter's debug loader, its key handling and Monaco's AMD loader would otherwise clash).
- **Switching Blocks ↔ C++ is instant.** Both editors stay loaded while a project is open (an `IndexedStack`; the
  hidden one is only not painted, and Flutter keeps its iframe in the page), so Blockly keeps its undo history.
  The C++ editor is created the first time its tab is shown (about half a second); after that a switch is one frame
  (~130 ms measured, including the test's polling). Leaving the editor (Home, Projects …) keeps them too: the
  editor page stays built offstage while a project is open (`Shell._pages`).
- **Zoom and pane sizes.** Blocks zoom with the toolbar (− / % / + / fit; click the % to go back to 90 %),
  Ctrl/⌘ + scroll or a trackpad pinch (a plain scroll moves the workspace), Ctrl/⌘ + = / − / 0, or Blockly's corner
  buttons; 40 % to 250 %. Ctrl/⌘ + scroll also zooms the C++ editor. The divider between the blocks and the C++ pane
  and the gap above the console can be dragged (double-click resets); the sizes are kept in Settings
  (`cppPaneWidth`, `consoleHeight`). While a divider is pressed the editor iframes ignore the pointer
  (`setEditorFramesInteractive`), or they would swallow the drag.
- **Menus, dialogs and focus over the editors.** A click over an iframe goes to the iframe even where Flutter paints on
  top of it. So while a menu (`Popover`) or a dialog / dropdown (a `PopupRoute`, via `EditorFramesObserver` in
  main.dart) is open, the iframes take no pointer (`coverEditorFrames`); a click beside a menu then closes it. A panel
  that floats over an editor but leaves the rest usable (Ask Cog on a narrow window) sits on a `FrameShield`, an
  invisible element that takes its clicks for Flutter (like package:pointer_interceptor). And a click anywhere outside
  the editors takes the keyboard focus back from their iframe, so Esc and the app's shortcuts reach the app.
- **The IDE's shortcuts inside the editors.** Keys typed in Blockly or Monaco stay in their iframe, so
  robocore_editors.js takes Ctrl/⌘ + S, R, U and I first (capture phase) and hands them to the app
  (`setIdeKeys` → `setEditorShortcutHandler` → Shell): Save, Verify, Upload, Ask Cog. That also stops the browser
  saving the page, reloading it (R) or showing its source (U), and Monaco's Ctrl/⌘ + I suggestions (Ctrl + Space
  still opens them). Blocks changed in the last 60 ms are sent first, so Verify checks what is on screen. Tests:
  `node --test test/js/robocore_editors.test.mjs`.
- **AppState stays the source of truth.** Every Blockly change sends the workspace (Blockly JSON), the C++ and the
  block count to `AppState.setBlockly`. The project saves them as `blockly` and `blocklyCode`; the main `.ino` follows
  the blocks until it is edited by hand (then the C++ pane offers *Use the blocks again*).
- **Old projects and the examples** still store blocks as `{setup, loop}` lists. `blocklyFromLists`
  (lib/engine/blockly_convert.dart) turns them into a Blockly workspace when they open. An edit in the old Flutter
  block editor (native apps) clears the Blockly workspace, so whichever editor changed the blocks last wins.
- **The C++ generator** (in robocore_editors.js) writes the same sketch as `genBlocks` for the old blocks: checked for
  all 15 example/board pairs (byte-identical), so the preview board, the compile server and the RoboCore library see
  no difference. New blocks: if / else, repeat, while, compare, and / or / not, true / false, arithmetic, random,
  variables (Blockly's), *USER pressed?*, *distance (cm)*, *line position*, *print value*, text.

## What was checked

- In the app (Chrome, 1440 × 900): Blink LED converts to Blockly; dragging *if*, *USER pressed?* and
  *set RGB LED* updates the C++ pane live; loose blocks are disabled; Verify (preview check) passes; the same sketch
  compiles on the compile server for the ESP32-S3 (300 KB, 0 problems).
- Monaco: Paper theme, JetBrains Mono, C++ tokens, file tabs, an ink squiggle and ruler mark from a problem.
- `flutter test` (60, including test/blockly_test.dart), `dart analyze`, the USB bridge tests.

## Not done yet

- Navy theme, font size, word wrap and autocomplete are passed to both editors but were not checked by eye.
- Verify problems → Monaco markers and *click a problem → jump to the line* are wired but not tried in the app.
- Monaco's prebuilt (AMD) build is deprecated upstream: bundle the ESM build with only the C++ parts later.
- No automated check of the JS generator in CI yet (it could run Blockly headless in Node against fixtures from Dart).
- Desktop / mobile apps: Blockly and Monaco need a WebView there (or the Electron route for desktop).
- Spec items not built: Cog, Quick Fix / Explain lens, hover links to the Arduino reference, comments export.
