// Blockly and Monaco for the web app. Each runs in web/robocore_editors.html (#blocks or #code)
// inside an iframe and is driven through window.rcEditor (web/robocore_editors.js), so its
// scripts, styles and keyboard shortcuts stay apart from Flutter's.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';

const kWebEditors = true;

extension type _Frame._(JSObject _) implements JSObject {
  external set src(String value);
  external _Style get style;
  external _Win? get contentWindow;
  external void addEventListener(String type, JSFunction listener);
}

extension type _Style._(JSObject _) implements JSObject {
  external set border(String value);
  external set width(String value);
  external set height(String value);
  external set display(String value);
}

extension type _Win._(JSObject _) implements JSObject {
  external _Api? get rcEditor;
}

extension type _Api._(JSObject _) implements JSObject {
  external _Blocks get blocks;
  external _Code get code;
}

extension type _Blocks._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> mount(String options, String? json, bool tidy, JSFunction onChange);
  external void load(String? json, bool tidy);
  external void setOptions(String options);
  external void undo();
  external void redo();
  external void clear();
  external int count();
}

extension type _Code._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> mount(String options, JSFunction onChange, JSFunction onCursor);
  external void setFile(String key, String text, bool readOnly);
  external void setOptions(String options);
  external void setMarkers(String key, String problems);
  external void reveal(int line, int column);
  external void find();
}

/// An iframe with robocore_editors.html#[mode]. [onReady] runs after every load, so an editor
/// whose frame the browser reloads comes back.
Widget _frame(String mode, void Function(_Api api) onReady) => HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (Object element) {
        final f = element as _Frame;
        f.style
          ..border = '0'
          ..width = '100%'
          ..height = '100%'
          ..display = 'block';
        f.addEventListener(
            'load',
            (() {
              final api = f.contentWindow?.rcEditor;
              if (api != null) onReady(api);
            }).toJS);
        f.src = 'robocore_editors.html#$mode';
      },
    );

/// Google Blockly with the RoboCore blocks. [onChange] gets the workspace (Blockly JSON), the C++
/// and the number of blocks after every change.
class BlocklyEditor extends StatefulWidget {
  const BlocklyEditor(
      {super.key, required this.projectId, required this.json, required this.tidy, required this.options, required this.onChange});
  final String projectId;

  /// The workspace to open; [tidy] lays it out first (for blocks converted from the old editor).
  final String? json;
  final bool tidy;

  /// name, board, pins, tonePins, userPin, theme.
  final Map<String, Object?> options;
  final void Function(String json, String code, int count) onChange;

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
      this.onCursor});
  final String fileKey, text;

  /// theme, fontSize, wrap, autocomplete, words.
  final Map<String, Object?> options;
  final bool readOnly;

  /// Problems in this file: line, column, message, severity.
  final List<Map<String, Object?>> problems;
  final void Function(String text)? onChange;
  final void Function(int line, int column)? onCursor;

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

  @override
  Widget build(BuildContext context) => _view;
}
