// Native apps: no Blockly or Monaco yet (they need a WebView). The editor uses BlocksView and CodeView.
import 'package:flutter/widgets.dart';

const kWebEditors = false;

Future<void> initWebEditors() async {}

void setEditorFramesInteractive(bool on) {}

void coverEditorFrames(bool on) {}

void setEditorShortcutHandler(void Function(String action)? handler) {}

class EditorFramesObserver extends NavigatorObserver {}

class FrameShield extends StatelessWidget {
  const FrameShield({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

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
  void undo() {}
  void redo() {}
  void clear() {}
  int get count => 0;
  void zoom(int dir) {}
  void zoomToFit() {}
  void resetZoom() {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

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
  void find() {}
  void reveal(int line, [int column = 1]) {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
