// Blockly and Monaco for the web app. Each runs in web/robocore_editors.html (#blocks or #code)
// inside an iframe and is driven through window.rcEditor (web/robocore_editors.js), so its
// scripts, styles and keyboard shortcuts stay apart from Flutter's.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';

const kWebEditors = true;

Future<void> initWebEditors() async {}

extension type _Frame._(JSObject _) implements JSObject {
  external set src(String value);
  external bool get isConnected;
  external _Style get style;
  external _Win? get contentWindow;
  external void addEventListener(String type, JSFunction listener);
}

extension type _Style._(JSObject _) implements JSObject {
  external set border(String value);
  external set width(String value);
  external set height(String value);
  external set display(String value);
  external set pointerEvents(String value);
}

extension type _Win._(JSObject _) implements JSObject {
  external _Api? get rcEditor;
}

extension type _Api._(JSObject _) implements JSObject {
  external _Blocks get blocks;
  external _Code get code;
  external void setIdeKeys(JSFunction handler);
}

extension type _Blocks._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> mount(
      String options, String? json, bool tidy, JSFunction onChange, JSFunction onZoom, JSFunction onSelect, JSFunction onHistory);
  external void load(String? json, bool tidy);
  external void setOptions(String options);
  external void undo();
  external void redo();
  external void clear();
  external int count();
  external void zoom(int dir);
  external void zoomToFit();
  external void resetZoom();
}

extension type _Code._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> mount(String options, JSFunction onChange, JSFunction onCursor, JSFunction? onExplain);
  external void setFile(String key, String text, bool readOnly);
  external void setOptions(String options);
  external void setMarkers(String key, String problems);
  external void reveal(int line, int column);
  external void find();
  external void action(String id);
}

@JS('document')
external _Doc get _document;

extension type _Doc._(JSObject _) implements JSObject {
  external _Focused? get activeElement;
  external void addEventListener(String type, JSFunction listener, JSAny options);
}

extension type _Focused._(JSObject _) implements JSObject {
  external String get tagName;
  external void blur();
}

final _frames = <_Frame>{};
var _focusReturns = false;
void Function(String action)? _ideKey;

/// Ctrl/⌘ + S, R, U and I typed inside Blockly or Monaco never reach Flutter (the iframe has the keys), so
/// the editors hand them over: [handler] gets 'save', 'verify', 'upload' or 'cog'.
void setEditorShortcutHandler(void Function(String action)? handler) => _ideKey = handler;

/// The page only sees a pointerdown outside both editors (inside one it goes to the iframe), but the
/// browser leaves the keyboard focus in the iframe, so Esc and Ctrl/⌘+S, R, U, I would never reach
/// Flutter after a click on the top bar or a menu. Take the focus back on such clicks.
void _returnFocusOnOutsideClicks() {
  if (_focusReturns) return;
  _focusReturns = true;
  _document.addEventListener(
      'pointerdown',
      ((JSObject _) {
        final a = _document.activeElement;
        if (a != null && a.tagName == 'IFRAME') a.blur();
      }).toJS,
      true.toJS);
}

var _dragging = false;
var _covers = 0;

void _applyPointer() {
  _frames.removeWhere((f) => !f.isConnected);
  for (final f in _frames) {
    f.style.pointerEvents = _dragging || _covers > 0 ? 'none' : 'auto';
  }
}

/// While a pane divider is dragged the editors' iframes must not take the pointer (it would stop
/// reaching Flutter as soon as it crossed one).
void setEditorFramesInteractive(bool on) {
  _dragging = !on;
  _applyPointer();
}

/// A click over an iframe goes to the iframe even where Flutter paints on top of it, so a menu or
/// dialog over an editor could not be clicked (the click landed in Blockly or Monaco). While one is
/// open the editors take no pointer; a click beside a menu then reaches Flutter and closes it.
void coverEditorFrames(bool on) {
  _covers = on ? _covers + 1 : (_covers > 0 ? _covers - 1 : 0);
  _applyPointer();
}

/// Covers the editors while a dialog or popup menu (a [PopupRoute]) is open.
class EditorFramesObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) coverEditorFrames(true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) coverEditorFrames(false);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) coverEditorFrames(false);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PopupRoute) coverEditorFrames(false);
    if (newRoute is PopupRoute) coverEditorFrames(true);
  }
}

/// Takes the clicks over its own area for Flutter: an invisible element above the editors' iframes
/// (the same trick as package:pointer_interceptor). For panels that float over an editor but leave
/// the rest of it usable, such as Ask Cog on a narrow window.
class FrameShield extends StatelessWidget {
  const FrameShield({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            isVisible: false,
            onElementCreated: (Object element) => (element as _Frame).style
              ..width = '100%'
              ..height = '100%',
          ),
        ),
        child,
      ]);
}

/// An iframe with robocore_editors.html#[mode]. [onReady] runs after every load, so an editor
/// whose frame the browser reloads comes back.
Widget _frame(String mode, void Function(_Api api) onReady) => HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (Object element) {
        final f = element as _Frame;
        _frames.add(f);
        _returnFocusOnOutsideClicks();
        f.style
          ..border = '0'
          ..width = '100%'
          ..height = '100%'
          ..display = 'block'
          ..pointerEvents = _dragging || _covers > 0 ? 'none' : 'auto';
        f.addEventListener(
            'load',
            (() {
              final api = f.contentWindow?.rcEditor;
              if (api == null) return;
              api.setIdeKeys(((JSString action) => _ideKey?.call(action.toDart)).toJS);
              onReady(api);
            }).toJS);
        f.src = 'robocore_editors.html#$mode';
      },
    );

/// Google Blockly with the RoboCore blocks. [onChange] gets the workspace (Blockly JSON), the C++
/// and the number of blocks after every change.
class BlocklyEditor extends StatefulWidget {
  const BlocklyEditor(
      {super.key,
      required this.projectId,
      required this.json,
      required this.tidy,
      required this.options,
      required this.onChange,
      this.onZoom,
      this.onSelect,
      this.onHistory});
  final String projectId;

  /// The workspace to open; [tidy] lays it out first (for blocks converted from the old editor).
  final String? json;
  final bool tidy;

  /// name, board, pins, tonePins, userPin, theme.
  final Map<String, Object?> options;
  final void Function(String json, String code, int count) onChange;

  /// The workspace scale after every zoom (1 = the starting size).
  final void Function(double scale)? onZoom;

  /// The selected block as JSON {type, label, cpp}, or '' when none is selected.
  final void Function(String json)? onSelect;

  /// Whether Undo and Redo have something to do.
  final void Function(bool canUndo, bool canRedo)? onHistory;

  @override
  State<BlocklyEditor> createState() => BlocklyEditorState();
}

class BlocklyEditorState extends State<BlocklyEditor> {
  _Blocks? _api;
  String? _json; // the latest workspace, so a reloaded frame comes back as it was
  late String _options = jsonEncode(widget.options);
  late final Widget _view = _frame('blocks', (api) => unawaited(_ready(api)));

  Future<void> _ready(_Api api) async {
    final b = api.blocks;
    _api = null;
    await b
        .mount(_options, _json ?? widget.json, _json == null && widget.tidy, ((JSString json, JSString code, JSNumber count) {
          _json = json.toDart;
          if (mounted) widget.onChange(_json!, code.toDart, count.toDartInt);
        }).toJS, ((JSNumber scale) {
          if (mounted) widget.onZoom?.call(scale.toDartDouble);
        }).toJS, ((JSString json) {
          if (mounted) widget.onSelect?.call(json.toDart);
        }).toJS, ((JSBoolean canUndo, JSBoolean canRedo) {
          if (mounted) widget.onHistory?.call(canUndo.toDart, canRedo.toDart);
        }).toJS)
        .toDart;
    _api = b;
  }

  @override
  void didUpdateWidget(BlocklyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = jsonEncode(widget.options);
    if (o != _options) {
      _options = o;
      _api?.setOptions(o);
    }
    if (widget.projectId != oldWidget.projectId) {
      _json = null;
      _api?.load(widget.json, widget.tidy);
    }
  }

  void undo() => _api?.undo();
  void redo() => _api?.redo();
  void clear() => _api?.clear();
  int get count => _api?.count() ?? 0;

  /// [dir] 1 zooms in, -1 out.
  void zoom(int dir) => _api?.zoom(dir);
  void zoomToFit() => _api?.zoomToFit();
  void resetZoom() => _api?.resetZoom();

  @override
  Widget build(BuildContext context) => _view;
}

/// Monaco showing one file at a time ([fileKey] names its model, so each file keeps its own undo
/// history). Text that differs from the editor's replaces it; typing calls [onChange].
class MonacoEditor extends StatefulWidget {
  const MonacoEditor(
      {super.key,
      required this.fileKey,
      required this.text,
      required this.options,
      this.readOnly = false,
      this.problems = const [],
      this.onChange,
      this.onCursor,
      this.onExplain});
  final String fileKey, text;

  /// theme, fontSize, wrap, autocomplete, words.
  final Map<String, Object?> options;
  final bool readOnly;

  /// Problems in this file: line, column, message, severity.
  final List<Map<String, Object?>> problems;
  final void Function(String text)? onChange;
  final void Function(int line, int column)? onCursor;

  /// "Explain with Cog" on a line (quick fix on a problem, or the context menu).
  final void Function(int line)? onExplain;

  @override
  State<MonacoEditor> createState() => MonacoEditorState();
}

class MonacoEditorState extends State<MonacoEditor> {
  _Code? _api;
  String? _key, _text, _problems;
  bool? _readOnly;
  late String _options = jsonEncode(widget.options);
  late final Widget _view = _frame('code', (api) => unawaited(_ready(api)));

  Future<void> _ready(_Api api) async {
    final c = api.code;
    _api = null;
    await c
        .mount(
            _options,
            ((JSString key, JSString text) {
              if (key.toDart != _key) return;
              _text = text.toDart;
              if (mounted) widget.onChange?.call(_text!);
            }).toJS,
            ((JSNumber line, JSNumber column) {
              if (mounted) widget.onCursor?.call(line.toDartInt, column.toDartInt);
            }).toJS,
            widget.onExplain == null
                ? null
                : ((JSNumber line) {
                    if (mounted) widget.onExplain?.call(line.toDartInt);
                  }).toJS)
        .toDart;
    _api = c;
    _key = null;
    _sync();
  }

  void _sync() {
    final c = _api;
    if (c == null) return;
    final w = widget;
    if (w.fileKey != _key || w.text != _text || w.readOnly != _readOnly) {
      _key = w.fileKey;
      _text = w.text;
      _readOnly = w.readOnly;
      _problems = null;
      c.setFile(w.fileKey, w.text, w.readOnly);
    }
    final p = jsonEncode(w.problems);
    if (p != _problems) {
      _problems = p;
      c.setMarkers(w.fileKey, p);
    }
  }

  @override
  void didUpdateWidget(MonacoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = jsonEncode(widget.options);
    if (o != _options) {
      _options = o;
      _api?.setOptions(o);
    }
    _sync();
  }

  void find() => _api?.find();
  void reveal(int line, [int column = 1]) => _api?.reveal(line, column);

  /// Runs a Monaco command by id ('undo', 'editor.action.commentLine' …).
  void action(String id) => _api?.action(id);

  @override
  Widget build(BuildContext context) => _view;
}
