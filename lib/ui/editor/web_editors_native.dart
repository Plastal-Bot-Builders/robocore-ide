// Blockly and Monaco for the macOS and Windows apps: the web app's page (web/robocore_editors.html, bundled for
// them in pubspec.yaml) in a WebView, so the desktop editors look and work like the web ones; lib/hw/page_server.dart
// serves it. The Mac uses WKWebView (webview_flutter), Windows WebView2 (web_editors_windows.dart). The other native
// apps keep the Flutter BlocksView and CodeView for now (kWebEditors is false there).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../hw/page_server.dart';
import '../widgets/ui_scale.dart';
import 'web_editors_windows.dart';

var _windows = false;

bool get kWebEditors => defaultTargetPlatform == TargetPlatform.macOS || _windows;

/// Turns the editors on in the Windows app when the WebView2 runtime is installed. Called once at start-up.
Future<void> initWebEditors() async {
  if (defaultTargetPlatform == TargetPlatform.windows) _windows = await webView2Installed();
}

// On macOS, Flutter takes the clicks wherever it paints over a WebView (menus, dialogs, the Cog panel) and
// a drag that starts in Flutter stays there, so the editors need none of the web app's iframe guards.

/// True while a split handle is held (SplitHandle calls this with false on press, true on release): the editors
/// then keep a steady size (_Steady).
final _resizing = ValueNotifier(false);

void setEditorFramesInteractive(bool on) => _resizing.value = !on;

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

/// A JavaScript call with JSON arguments (JSON is valid JavaScript).
String _js(String fn, [List<Object?> args = const []]) => '$fn(${args.map(jsonEncode).join(',')})';

/// One editor: robocore_editors.html#[mode] in a WebView. The page answers on the RoboCoreHost channel
/// with [event, ...args] (see "The desktop app" in robocore_editors.js); [onLoaded] runs after every load,
/// so a page the WebView reloads comes back, as the web app's iframes do.
class _Page {
  _Page(this.mode, this.onLoaded, this.onEvent) {
    final url = servePages().then((origin) {
      _home = origin;
      return origin.replace(path: '/robocore_editors.html', fragment: mode);
    });
    if (_windows) {
      _win = WindowsEditorPage(url, _message);
      return;
    }
    final c = _mac = WebViewController();
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('RoboCoreHost', onMessageReceived: (m) => _message(m.message))
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: _navigate));
    unawaited(url.then(c.loadRequest));
  }

  final String mode;
  final void Function() onLoaded;
  final void Function(String event, List<Object?> args) onEvent;
  WebViewController? _mac;
  WindowsEditorPage? _win;
  late final Widget _webView = _win?.view() ?? WebViewWidget(controller: _mac!);
  Uri? _home;

  /// The WebView, under the page's background until the editor is up (while it loads, a WebView is
  /// blank, and black in dark mode).
  Widget view({required bool ready, required Object? theme}) => Stack(fit: StackFit.expand, children: [
        _Steady(child: _webView),
        if (!ready) ColoredBox(color: theme == 'navy' ? const Color(0xFF17253A) : const Color(0xFFFFFCF5)),
      ]);

  /// The page stays the page: links (e.g. in a hover) do not replace it.
  NavigationDecision _navigate(NavigationRequest r) {
    final u = Uri.tryParse(r.url);
    return u != null && u.origin == _home?.origin && u.path == '/robocore_editors.html'
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  void _message(String json) {
    final List<Object?> a;
    try {
      a = jsonDecode(json) as List<Object?>;
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

  void run(String js) {
    if (_win != null) return _win!.run(js);
    unawaited(_mac!.runJavaScript(js).catchError((Object e) {
      debugPrint('RoboCore editor ($mode): $e');
    }));
  }
}

/// Where the WebView sits in the app (the same widgets throughout, so the page is never rebuilt):
/// - Unscaled by the display size (UiScale): a scaled WebView would be blurry, so it is drawn at the screen's own
///   size and the page grows its content instead (the zoom option).
/// - Steady while a split handle is held: a WebView that grows shows black where WebKit hasn't drawn yet, a strip
///   that widens the faster the handle is dragged. So meanwhile it is as big as the window, clipped to its box, and a
///   growing pane uncovers page that is already drawn; on release it takes its box's size again.
/// - A point bigger than its box, rounded up: WebKit leaves a pane's last fraction of a point unpainted, black in
///   dark mode, which showed as a dark line along the bottom of the editors. The extra is clipped away.
class _Steady extends StatelessWidget {
  const _Steady({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    final s = UiScale.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _resizing,
      child: child,
      builder: (context, resizing, child) => LayoutBuilder(builder: (context, box) {
        final w = resizing && window.width > box.maxWidth ? window.width : box.maxWidth;
        final h = resizing && window.height > box.maxHeight ? window.height : box.maxHeight;
        final fw = (w * s).ceilToDouble() + 1, fh = (h * s).ceilToDouble() + 1; // the WebView, in its own points
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: w,
            maxWidth: w,
            minHeight: h,
            maxHeight: h,
            child: Transform.scale(
              scale: 1 / s,
              alignment: Alignment.topLeft,
              child: OverflowBox(alignment: Alignment.topLeft, minWidth: fw, maxWidth: fw, minHeight: fh, maxHeight: fh, child: child),
            ),
          ),
        );
      }),
    );
  }
}

/// The options the page gets: the editor's own, and the display size it draws its content at (see _Steady).
String _withZoom(BuildContext context, Map<String, Object?> options) => jsonEncode({...options, 'zoom': UiScale.of(context)});

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
  late String _options = _withZoom(context, widget.options);
  late final _page = _Page('blocks', _loaded, _event);

  void _sendOptions() {
    final o = _withZoom(context, widget.options);
    if (o == _options) return;
    _options = o;
    _call('setOptions', [o]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sendOptions(); // the display size
  }

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
    _sendOptions();
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
  late String _options = _withZoom(context, widget.options);
  late final _page = _Page('code', _loaded, _event);

  void _sendOptions() {
    final o = _withZoom(context, widget.options);
    if (o == _options) return;
    _options = o;
    _call('setOptions', [o]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sendOptions(); // the display size
  }

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
    _sendOptions();
    _sync();
  }

  void find() => _call('find');
  void reveal(int line, [int column = 1]) => _call('reveal', [line, column]);

  /// Runs a Monaco command by id ('undo', 'editor.action.commentLine' …).
  void action(String id) => _call('action', [id]);

  @override
  Widget build(BuildContext context) => _page.view(ready: _ready, theme: widget.options['theme']);
}
