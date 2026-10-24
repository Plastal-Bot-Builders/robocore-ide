// Blockly and Monaco for the macOS app: the web app's page (web/robocore_editors.html, bundled for macOS in
// pubspec.yaml) in a WebView, so the desktop editors look and work like the web ones. A small server on
// 127.0.0.1 serves the page from the app's assets, so Monaco's workers and the fonts load as they do on the
// web. The other native apps keep the Flutter BlocksView and CodeView for now (kWebEditors is false there).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool get kWebEditors => defaultTargetPlatform == TargetPlatform.macOS;

// On macOS, Flutter takes the clicks wherever it paints over a WebView (menus, dialogs, the Cog panel) and
// a drag that starts in Flutter stays there, so the editors need none of the web app's iframe guards.
void setEditorFramesInteractive(bool on) {}

void coverEditorFrames(bool on) {}

class EditorFramesObserver extends NavigatorObserver {}

class FrameShield extends StatelessWidget {
  const FrameShield({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

void Function(String action)? _ideKey;

/// Ctrl/⌘ + S, R, U and I typed inside Blockly or Monaco never reach Flutter (the WebView has the keys), so
/// the editors hand them over: [handler] gets 'save', 'verify', 'upload' or 'cog'.
void setEditorShortcutHandler(void Function(String action)? handler) => _ideKey = handler;

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'json': 'application/json',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'gif': 'image/gif',
  'cur': 'image/x-icon',
  'ttf': 'font/ttf',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
};

Future<Uri>? _origin;

/// The page and web/vendor come from the assets under web/, and the fonts from assets/fonts/, which the
/// page asks for as assets/assets/fonts/ (where the web build puts them).
Future<Uri> _serve() => _origin ??= () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path.substring(1);
        final key = path.startsWith('assets/assets/fonts/') ? path.substring(7) : 'web/$path';
        final res = req.response;
        try {
          if (req.method != 'GET' || path.startsWith('assets/') && !key.startsWith('assets/fonts/')) {
            throw StateError('not served');
          }
          final data = await rootBundle.load(key);
          res.headers
            ..set(HttpHeaders.contentTypeHeader, _types[key.split('.').last] ?? 'application/octet-stream')
            ..set(HttpHeaders.cacheControlHeader, 'no-store');
          res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        } catch (_) {
          res.statusCode = HttpStatus.notFound;
        }
        await res.close();
      });
      return Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    }();

/// A JavaScript call with JSON arguments (JSON is valid JavaScript).
String _js(String fn, [List<Object?> args = const []]) => '$fn(${args.map(jsonEncode).join(',')})';

/// One editor: robocore_editors.html#[mode] in a WebView. The page answers on the RoboCoreHost channel
/// with [event, ...args] (see "The desktop app" in robocore_editors.js); [onLoaded] runs after every load,
/// so a page the WebView reloads comes back, as the web app's iframes do.
class _Page {
  _Page(this.mode, this.onLoaded, this.onEvent) {
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('RoboCoreHost', onMessageReceived: _message)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: _navigate));
    unawaited(_serve().then((origin) {
      _home = origin;
      return controller.loadRequest(origin.replace(path: '/robocore_editors.html', fragment: mode));
    }));
  }

  final String mode;
  final void Function() onLoaded;
  final void Function(String event, List<Object?> args) onEvent;
  final controller = WebViewController();
  late final Widget _webView = WebViewWidget(controller: controller);
  Uri? _home;

  /// The WebView, under the page's background until the editor is up (while it loads, a WebView is
  /// blank, and black in dark mode).
  Widget view({required bool ready, required Object? theme}) => Stack(fit: StackFit.expand, children: [
        _webView,
        if (!ready) ColoredBox(color: theme == 'navy' ? const Color(0xFF17253A) : const Color(0xFFFFFCF5)),
      ]);

  /// The page stays the page: links (e.g. in a hover) do not replace it.
  NavigationDecision _navigate(NavigationRequest r) {
    final u = Uri.tryParse(r.url);
    return u != null && u.origin == _home?.origin && u.path == '/robocore_editors.html'
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  void _message(JavaScriptMessage m) {
    final List<Object?> a;
    try {
      a = jsonDecode(m.message) as List<Object?>;
    } on FormatException {
      return;
    }
    final event = a.first as String;
    final args = a.sublist(1);
    switch (event) {
      case 'loaded':
        onLoaded();
      case 'key':
        _ideKey?.call(args.first as String);
      case 'error':
        debugPrint('RoboCore editor ($mode): ${args.first}');
      default:
        onEvent(event, args);
    }
  }

  void run(String js) => unawaited(controller.runJavaScript(js).catchError((Object e) {
        debugPrint('RoboCore editor ($mode): $e');
      }));
}

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
  var _ready = false; // mounted in the page; calls before that are dropped, as in the web app
  String? _json; // the latest workspace, so a reloaded page comes back as it was
  var _count = 0;
  late String _options = jsonEncode(widget.options);
  late final _page = _Page('blocks', _loaded, _event);

  void _setReady(bool on) {
    if (mounted && on != _ready) setState(() => _ready = on);
  }

  void _loaded() {
    _setReady(false);
    _page.run(_js('rcNative.mountBlocks', [_options, _json ?? widget.json, _json == null && widget.tidy]));
  }

  void _event(String event, List<Object?> a) {
    switch (event) {
      case 'mounted':
        _setReady(true);
      case 'change':
        _json = a[0] as String;
        _count = (a[2] as num).toInt();
        if (mounted) widget.onChange(_json!, a[1] as String, _count);
      case 'zoom':
        if (mounted) widget.onZoom?.call((a[0] as num).toDouble());
      case 'select':
        if (mounted) widget.onSelect?.call(a[0] as String);
      case 'history':
        if (mounted) widget.onHistory?.call(a[0] as bool, a[1] as bool);
    }
  }

  void _call(String method, [List<Object?> args = const []]) {
    if (_ready) _page.run(_js('rcEditor.blocks.$method', args));
  }

  @override
  void didUpdateWidget(BlocklyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = jsonEncode(widget.options);
    if (o != _options) {
      _options = o;
      _call('setOptions', [o]);
    }
    if (widget.projectId != oldWidget.projectId) {
      _json = null;
      _call('load', [widget.json, widget.tidy]);
    }
  }

  void undo() => _call('undo');
  void redo() => _call('redo');
  void clear() => _call('clear');
  int get count => _count;

  /// [dir] 1 zooms in, -1 out.
  void zoom(int dir) => _call('zoom', [dir]);
  void zoomToFit() => _call('zoomToFit');
  void resetZoom() => _call('resetZoom');

  @override
  Widget build(BuildContext context) => _page.view(ready: _ready, theme: widget.options['theme']);
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
  var _ready = false;
  String? _key, _text, _problems;
  bool? _readOnly;
  late String _options = jsonEncode(widget.options);
  late final _page = _Page('code', _loaded, _event);

  void _setReady(bool on) {
    if (mounted && on != _ready) setState(() => _ready = on);
  }

  void _loaded() {
    _setReady(false);
    _page.run(_js('rcNative.mountCode', [_options, widget.onExplain != null]));
  }

  void _event(String event, List<Object?> a) {
    switch (event) {
      case 'mounted':
        _setReady(true);
        _key = null;
        _sync();
      case 'change':
        if (a[0] != _key) return;
        _text = a[1] as String;
        if (mounted) widget.onChange?.call(_text!);
      case 'cursor':
        if (mounted) widget.onCursor?.call((a[0] as num).toInt(), (a[1] as num).toInt());
      case 'explain':
        if (mounted) widget.onExplain?.call((a[0] as num).toInt());
    }
  }

  void _call(String method, [List<Object?> args = const []]) {
    if (_ready) _page.run(_js('rcEditor.code.$method', args));
  }

  void _sync() {
    if (!_ready) return;
    final w = widget;
    if (w.fileKey != _key || w.text != _text || w.readOnly != _readOnly) {
      _key = w.fileKey;
      _text = w.text;
      _readOnly = w.readOnly;
      _problems = null;
      _call('setFile', [w.fileKey, w.text, w.readOnly]);
    }
    final p = jsonEncode(w.problems);
    if (p != _problems) {
      _problems = p;
      _call('setMarkers', [w.fileKey, p]);
    }
  }

  @override
  void didUpdateWidget(MonacoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = jsonEncode(widget.options);
    if (o != _options) {
      _options = o;
      _call('setOptions', [o]);
    }
    _sync();
  }

  void find() => _call('find');
  void reveal(int line, [int column = 1]) => _call('reveal', [line, column]);

  @override
  Widget build(BuildContext context) => _page.view(ready: _ready, theme: widget.options['theme']);
}
