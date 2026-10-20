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
  (~130 ms measured, including the test's polling). Leaving the editor (Home, Projects …) still closes them.
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
