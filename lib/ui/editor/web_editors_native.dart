// Blockly and Monaco for the Windows app. The same page as the web app (web/robocore_editors.html,
// #blocks or #code) runs in a WebView2 (package:webview_windows). The page's files are copied next to
// RoboCore.exe (data/editors, windows/CMakeLists.txt) and served as https://robocore.editor/.
// web/robocore_editors_native.js turns the app's messages into window.rcEditor calls and posts the
// editors' callbacks back.
//
// The WebView is drawn by Flutter (a texture), so menus, dialogs and dividers over it need none of the
// iframe tricks the web app needs: setEditorFramesInteractive, coverEditorFrames and FrameShield do nothing.
// Other platforms, the tests, and a PC without the WebView2 runtime keep the Flutter BlocksView and CodeView.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart';

bool _enabled = false;
bool get kWebEditors => _enabled;

String _folder = '';
String _bridge = '';
const _host = 'robocore.editor';

/// Turns the editors on when this is Windows, the WebView2 runtime is installed and the editor files are
/// next to the app. Called once from main().
Future<void> initWebEditors() async {
  if (!Platform.isWindows) return;
  try {
    final dir = '${File(Platform.resolvedExecutable).parent.path}\\data\\editors';
    final bridge = File('$dir\\robocore_editors_native.js');
    if (!File('$dir\\robocore_editors.html').existsSync() || !bridge.existsSync()) return;
    if (await WebviewController.getWebViewVersion() == null) return;
    _folder = dir;
    _bridge = await bridge.readAsString();
    _enabled = true;
  } catch (_) {
    _enabled = false;
  }
}

void Function(String action)? _ideKey;

/// Ctrl + S, R, U, I, B and J typed inside Blockly or Monaco: [handler] gets 'save', 'verify', 'upload', 'cog',
/// 'sidebar' or 'console'.
void setEditorShortcutHandler(void Function(String action)? handler) => _ideKey = handler;

void setEditorFramesInteractive(bool on) {}

void coverEditorFrames(bool on) {}

class EditorFramesObserver extends NavigatorObserver {}

class FrameShield extends StatelessWidget {
  const FrameShield({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// One WebView showing robocore_editors.html#[mode]. [onReady] runs after every load (to mount the editor
/// again if the page reloads), [onCallback] for every editor callback.
class _Page {
  _Page(this.mode, {required this.onReady, required this.onCallback, required this.onChanged});
  final String mode;
  final void Function() onReady;
  final void Function(String name, List<dynamic> args) onCallback;
  final void Function() onChanged;
  final controller = WebviewController();
  StreamSubscription<dynamic>? _messages;
  bool mounted = false;
  bool _disposed = false;

  Future<void> start() async {
    try {
      await controller.initialize();
      if (_disposed) return;
      await controller.setBackgroundColor(const Color(0x00000000));
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.addVirtualHostNameMapping(_host, _folder, WebviewHostResourceAccessKind.allow);
      await controller.addScriptToExecuteOnDocumentCreated(_bridge);
      _messages = controller.webMessage.listen(_onMessage);
      await controller.loadUrl('https://$_host/robocore_editors.html#$mode');
      if (!_disposed) onChanged();
    } catch (e) {
      debugPrint('RoboCore editor ($mode) did not start: $e');
    }
  }

  void _onMessage(dynamic m) {
    if (m is! Map) return;
    switch (m['t']) {
      case 'ready':
        mounted = false;
        onReady();
      case 'mounted':
        mounted = true;
        onCallback('mounted', const []);
      case 'cb':
        final name = '${m['name']}';
        final args = (m['args'] as List?) ?? const [];
        if (name == 'ideKey') {
          if (args.isNotEmpty) _ideKey?.call('${args.first}');
        } else {
          onCallback(name, args);
        }
      case 'error':
        debugPrint('RoboCore editor ($mode): ${m['message']}');
    }
  }

  /// Calls window.rcEditor.[call](...args) in the page.
  void call(String call, [List<Object?> args = const []]) {
    if (_disposed || !controller.value.isInitialized) return;
    unawaited(controller.postWebMessage(jsonEncode({'call': call, 'args': args})));
  }

  Widget view() => controller.value.isInitialized ? Webview(controller) : const SizedBox.expand();

  void dispose() {
    _disposed = true;
    unawaited(_messages?.cancel());
    unawaited(controller.dispose());
  }
}

int _int(Object? v) => v is num ? v.toInt() : 0;

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
  final String? json;
  final bool tidy;
  final Map<String, Object?> options;
  final void Function(String json, String code, int count) onChange;
  final void Function(double scale)? onZoom;
  final void Function(String json)? onSelect;
  final void Function(bool canUndo, bool canRedo)? onHistory;

  @override
  State<BlocklyEditor> createState() => BlocklyEditorState();
}

class BlocklyEditorState extends State<BlocklyEditor> {
  late final _Page _page = _Page('blocks', onReady: _mount, onCallback: _onCallback, onChanged: _rebuild);
  String? _json; // the latest workspace, so a reloaded page comes back as it was
  late String _options = jsonEncode(widget.options);
  int _count = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_page.start());
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _mount() => _page.call('blocks.mount', [_options, _json ?? widget.json, _json == null && widget.tidy]);

  void _onCallback(String name, List<dynamic> a) {
    if (!mounted) return;
    switch (name) {
      case 'change':
        _json = '${a[0]}';
        _count = _int(a[2]);
        widget.onChange(_json!, '${a[1]}', _count);
      case 'zoom':
        final scale = a.isEmpty ? null : a[0];
        if (scale is num) widget.onZoom?.call(scale.toDouble());
      case 'select':
        widget.onSelect?.call(a.isEmpty ? '' : '${a[0]}');
      case 'history':
        widget.onHistory?.call(a[0] == true, a[1] == true);
    }
  }

  @override
  void didUpdateWidget(BlocklyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = jsonEncode(widget.options);
    if (o != _options) {
      _options = o;
      if (_page.mounted) _page.call('blocks.setOptions', [o]);
    }
    if (widget.projectId != oldWidget.projectId) {
      _json = null;
      if (_page.mounted) _page.call('blocks.load', [widget.json, widget.tidy]);
    }
  }

  void undo() => _page.call('blocks.undo');
  void redo() => _page.call('blocks.redo');
  void clear() => _page.call('blocks.clear');

  /// The number of blocks after the last change.
  int get count => _count;

  /// [dir] 1 zooms in, -1 out.
  void zoom(int dir) => _page.call('blocks.zoom', [dir]);
  void zoomToFit() => _page.call('blocks.zoomToFit');
  void resetZoom() => _page.call('blocks.resetZoom');

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _page.view();
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
  final Map<String, Object?> options;
  final bool readOnly;
  final List<Map<String, Object?>> problems;
  final void Function(String text)? onChange;
  final void Function(int line, int column)? onCursor;
  final void Function(int line)? onExplain;

  @override
  State<MonacoEditor> createState() => MonacoEditorState();
}

class MonacoEditorState extends State<MonacoEditor> {
  late final _Page _page = _Page('code', onReady: _mount, onCallback: _onCallback, onChanged: _rebuild);
  String? _key, _text, _problems;
  bool? _readOnly;
  late String _options = jsonEncode(widget.options);

  @override
  void initState() {
    super.initState();
    unawaited(_page.start());
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _mount() => _page.call('code.mount', [_options, widget.onExplain != null]);

  void _onCallback(String name, List<dynamic> a) {
    if (!mounted) return;
    switch (name) {
      case 'mounted':
        _key = null;
        _sync();
      case 'change':
        if ('${a[0]}' != _key) return;
        _text = '${a[1]}';
        widget.onChange?.call(_text!);
      case 'cursor':
        widget.onCursor?.call(_int(a[0]), _int(a[1]));
      case 'explain':
        widget.onExplain?.call(_int(a[0]));
    }
  }

  void _sync() {
    if (!_page.mounted) return;
    final w = widget;
    if (w.fileKey != _key || w.text != _text || w.readOnly != _readOnly) {
      _key = w.fileKey;
      _text = w.text;
      _readOnly = w.readOnly;
      _problems = null;
      _page.call('code.setFile', [w.fileKey, w.text, w.readOnly]);
    }
    final p = jsonEncode(w.problems);
    if (p != _problems) {
      _problems = p;
      _page.call('code.setMarkers', [w.fileKey, p]);
    }
  }

  @override
  void didUpdateWidget(MonacoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = jsonEncode(widget.options);
    if (o != _options) {
      _options = o;
      if (_page.mounted) _page.call('code.setOptions', [o]);
    }
    _sync();
  }

  void find() => _page.call('code.find');
  void reveal(int line, [int column = 1]) => _page.call('code.reveal', [line, column]);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _page.view();
}
