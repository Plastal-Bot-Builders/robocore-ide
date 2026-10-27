// The editor: Blocks / Code card, console panel and the board card.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/arduino_api.dart';
import '../../data/catalog.dart';
import '../../engine/blockly_convert.dart';
import '../../state/app_state.dart';
import '../../state/cog.dart';
import '../../state/models.dart';
import '../../state/sim_board.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../cog/cog_panel.dart';
import '../dialogs.dart' show DialogFrame, FieldLabel;
import '../mac_app.dart' show editorMenuCommand;
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/serial_log.dart';
import '../widgets/split_handle.dart';
import 'blocks_view.dart';
import 'code_view.dart';
import 'web_editors.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  bool _canUndo = false, _canRedo = false; // Blockly's undo stack (BK-09)
  final Map<String, GlobalKey<CodeViewState>> _keys = {};
  GlobalKey<CodeViewState>? _active;

  // Web app: Blockly and Monaco (web_editors.dart) instead of BlocksView and CodeView.
  final _blockly = GlobalKey<BlocklyEditorState>();
  final _monaco = GlobalKey<MonacoEditorState>();
  final _preview = GlobalKey<MonacoEditorState>();

  // Pane sizes while a divider is being dragged; saved to Settings when the drag ends.
  double? _cppWidth, _consoleHeight;

  @override
  void initState() {
    super.initState();
    editorMenuCommand = _menuCommand;
  }

  @override
  void dispose() {
    if (editorMenuCommand == _menuCommand) editorMenuCommand = null;
    super.dispose();
  }

  /// The Mac menu bar's editor commands: Edit (Undo, Comment, Find …) and View (Zoom). Zoom is Blockly's
  /// zoom in the blocks and the font size in the code.
  void _menuCommand(String id) {
    final s = AppScope.read(context);
    final p = s.cur;
    if (p == null) return;
    final blocks = p.mode == 'blocks';
    final code = _monaco.currentState;
    void font(int size) => s.updateSettings((st) => st.fontSize = size.clamp(10, 24));
    switch (id) {
      case 'undo':
        blocks ? _blockly.currentState?.undo() : code?.action('undo');
      case 'redo':
        blocks ? _blockly.currentState?.redo() : code?.action('redo');
      case 'comment':
        code?.action('editor.action.commentLine');
      case 'indent':
        code?.action('editor.action.indentLines');
      case 'outdent':
        code?.action('editor.action.outdentLines');
      case 'find':
        code?.find();
      case 'goToLine':
        code?.action('editor.action.gotoLine');
      case 'zoomIn':
        blocks ? _blockly.currentState?.zoom(1) : font(s.settings.fontSize + 1);
      case 'zoomOut':
        blocks ? _blockly.currentState?.zoom(-1) : font(s.settings.fontSize - 1);
      case 'zoomReset':
        blocks ? _blockly.currentState?.resetZoom() : font(13);
    }
  }

  // One CodeView per project + file, so switching tabs loads the right text.
  GlobalKey<CodeViewState> _codeKeyFor(String pid, int fi) =>
      _active = _keys.putIfAbsent('$pid/$fi', () => GlobalKey<CodeViewState>());

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final p = s.cur!;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 760;
    final showBoard = width >= 1000 && !s.cog.open;
    final fi = s.file.clamp(0, p.files.length - 1).toInt();
    final f = p.files[fi];

    Widget seg(String m, String label) {
      final on = p.mode == m;
      return Hover(
        onTap: () => s.setMode(m),
        builder: (context, h) => Container(
          height: 30,
          padding: EdgeInsets.only(left: 12, right: phone ? 12 : 14),
          decoration: BoxDecoration(color: on ? c.ink : (h ? c.surface : Colors.transparent), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            RcIcon(m == 'blocks' ? 'blocks' : 'code', size: 16, color: on ? c.bg : c.muted),
            if (!phone || on) ...[
              const SizedBox(width: 8),
              Text(label, style: tLabel(c, color: on ? c.bg : c.muted)),
            ],
          ]),
        ),
      );
    }

    final openTabs = [for (var i = 0; i < p.files.length; i++) if (!s.closedTabs.contains(i)) i];
    final tabs = p.mode == 'code'
        ? Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final i in openTabs)
                  Container(
                    height: 36,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.only(left: 10, right: 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: i == fi ? c.ink : Colors.transparent, width: 2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Hover(
                        onTap: () => s.openFile(i),
                        builder: (context, h) => Row(mainAxisSize: MainAxisSize.min, children: [
                          RcIcon('file', size: 16, color: c.ink),
                          const SizedBox(width: 8),
                          Text(p.files[i].name,
                              style: tLabel(c, color: i == fi ? c.ink : c.faint, w: i == fi ? FontWeight.w600 : FontWeight.w500)),
                        ]),
                      ),
                      if (openTabs.length > 1) ...[
                        const SizedBox(width: 8),
                        IconBtn('x', onTap: () => s.closeTab(i), tip: 'Close tab', size: 18, iconSize: 14),
                      ],
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: IconBtn('plus', onTap: () => _newTab(context, s, p), tip: 'New tab', size: 28, iconSize: 16),
                ),
              ]),
            ),
          )
        : null;

    final toolbar = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line2))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: c.sunk, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [seg('blocks', 'Blocks'), const SizedBox(width: 2), seg('code', 'Code')]),
        ),
        const SizedBox(width: 12),
        if (tabs != null) tabs else const Spacer(),
        if (tabs != null) const SizedBox(width: 8),
        if (p.mode == 'code')
          IconBtn('search',
              onTap: () => kWebEditors ? _monaco.currentState?.find() : _active?.currentState?.toggleFind(), tip: 'Find')
        else ...[
          // Zoom is on the canvas (Blockly's buttons, Ctrl/Cmd + wheel, pinch, Ctrl +/−/0), as in the design.
          if (kWebEditors && width >= 900)
            IconBtn('code',
                onTap: () => s.updateSettings((st) => st.showCpp = !st.showCpp),
                active: s.settings.showCpp,
                tip: s.settings.showCpp ? 'Hide the C++ from the blocks' : 'Show the C++ from the blocks'),
          // Greyed out when there is nothing to undo or redo (BK-09).
          IconBtn('undo', onTap: kWebEditors ? (_canUndo ? () => _blockly.currentState?.undo() : null) : s.undo, tip: 'Undo ($kMod+Z)'),
          IconBtn('redo', onTap: kWebEditors ? (_canRedo ? () => _blockly.currentState?.redo() : null) : s.redo, tip: 'Redo ($kMod+Shift+Z)'),
          IconBtn('trash', tip: 'Delete all blocks', onTap: () => _confirmClear(context, s, p)),
        ],
      ]),
    );

    final errLines = {for (final e in s.problems) if (e.file == f.name && e.isError) e.line};
    final Widget main;
    if (!kWebEditors) {
      main = p.mode == 'blocks'
          ? const BlocksView()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _codeBanner(context, s, c, p, fi),
              Expanded(child: CodeView(key: _codeKeyFor(p.id, fi), initial: f.content, fileName: f.name, errorLines: errLines)),
            ]);
    } else {
      // Both editors stay loaded while the project is open, so Blocks ↔ C++ is instant and Blockly
      // keeps its undo history; the hidden one is only not painted (its iframe stays in the page).
      main = IndexedStack(
        index: p.mode == 'blocks' ? 0 : 1,
        sizing: StackFit.expand,
        children: [
          _blocklyArea(s, c, p, width),
          // The banner always takes this slot, so Monaco's frame never moves (moving it would reload it).
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_codeBanner(context, s, c, p, fi), Expanded(child: _monacoFor(s, c, p, fi))]),
        ],
      );
      _takeGotoLine(s, p);
    }

    final edCard = RcCard(child: Column(children: [toolbar, Expanded(child: main)]));
    final panel = ConsolePanel(boardTab: !showBoard);
    final pad = phone ? 8.0 : 12.0;
    final cogBeside = width >= 1000;

    final content = Padding(
      padding: EdgeInsets.all(pad),
      child: LayoutBuilder(builder: (context, box) {
        // The console keeps 120 px at least and leaves the editor 200 px at least (also in a short window,
        // e.g. a Mac window tiled to a quarter of the screen).
        final maxConsole = (box.maxHeight - pad - 200).clamp(120.0, double.infinity);
        final consoleHeight = (phone ? 220.0 : _consoleHeight ?? s.settings.consoleHeight).clamp(120.0, maxConsole);
        return Column(children: [
          Expanded(child: edCard),
          if (s.panelOpen && !phone)
            SplitHandle(
              axis: Axis.vertical,
              thickness: pad,
              onDrag: (dy) => setState(() => _consoleHeight = consoleHeight - dy),
              onEnd: () {
                final h = consoleHeight;
                _consoleHeight = null;
                s.updateSettings((st) => st.consoleHeight = h);
              },
              onReset: () => s.updateSettings((st) => st.consoleHeight = Settings.defaultConsoleHeight),
            )
          else
            SizedBox(height: pad),
          if (!s.panelOpen)
            SizedBox(height: 42, child: panel)
          else
            SizedBox(
              height: consoleHeight,
              child: showBoard
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: panel),
                      const SizedBox(width: 12),
                      SizedBox(width: 280, child: RcCard(child: SingleChildScrollView(child: BoardCard(boardId: p.board)))),
                    ])
                  : panel,
            ),
        ]);
      }),
    );

    // The editor stays the first child in the same place whether Cog is open or not, so the
    // Blockly and Monaco frames are never moved (moving them would reload them).
    return Stack(children: [
      Positioned.fill(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: content),
          if (s.cog.open && cogBeside) Padding(padding: EdgeInsets.fromLTRB(0, pad, pad, pad), child: const SizedBox(width: 352, child: CogPanel())),
        ]),
      ),
      if (s.cog.open && !cogBeside)
        Positioned(top: pad, right: pad, bottom: pad, width: math.min(400, width - 2 * pad), child: const FrameShield(child: CogPanel())),
    ]);
  }

  /// "Explain with Cog" on a line of code: the problem on (or nearest to) that line, else the line itself.
  void _explainLine(AppState s, String file, int line) {
    final here = [for (final e in s.problems) if (e.file == file) e];
    if (here.isEmpty) {
      s.cog.ask('Explain line $line of $file.');
      return;
    }
    here.sort((a, b) => (a.line - line).abs().compareTo((b.line - line).abs()));
    s.cog.explainError(here.first);
  }

  Map<String, Object?> _monacoOptions(AppState s, RC c) => {
        'theme': c.dark ? 'navy' : 'paper',
        'fontSize': s.settings.fontSize,
        'wrap': s.settings.wrap,
        'autocomplete': s.settings.autocomplete,
        'words': [
          for (final e in kApi) [e.name, e.params, e.doc, e.url]
        ],
      };

  /// Blockly, and beside it (wide windows) the C++ the blocks make, read-only.
  Widget _blocklyArea(AppState s, RC c, Project p, double width) {
    final editor = BlocklyEditor(
      key: _blockly,
      projectId: p.id,
      json: p.blockly ?? blocklyFromLists(p.setup, p.loop),
      tidy: p.blockly == null,
      options: {
        'name': p.name,
        'board': p.board,
        'pins': pinOptions(p.board),
        'tonePins': pinOptions(p.board, tone: true),
        'analogPins': pinOptions(p.board, analog: true),
        'userPin': RoboCoreV2Pins.userButton,
        'led': kBoards[p.board]!.led,
        'theme': c.dark ? 'navy' : 'paper',
      },
      onChange: (json, code, count) => s.setBlockly(json, code, count: count),
      onHistory: (u, r) => setState(() {
        _canUndo = u;
        _canRedo = r;
      }),
      onSelect: (json) {
        if (json.isEmpty) return s.cog.selectBlock(null);
        final b = (jsonDecode(json) as Map).cast<String, dynamic>();
        s.cog.selectBlock(CogBlock(type: '${b['type']}', label: '${b['label']}', cpp: '${b['cpp']}'));
      },
    );
    return LayoutBuilder(builder: (context, box) {
      // Blocks keep at least 400 px (the toolbox takes ~150), the C++ pane at least 240 px.
      const minBlocks = 400.0, minCpp = 240.0, handle = 7.0;
      final show = s.settings.showCpp && width >= 900 && box.maxWidth >= minBlocks + minCpp + handle;
      final cppWidth = (_cppWidth ?? s.settings.cppPaneWidth).clamp(minCpp, (box.maxWidth - minBlocks - handle).clamp(minCpp, double.infinity));
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: editor),
        // Hidden, the C++ pane keeps its editor loaded (and takes no room).
        Visibility(
          visible: show,
          maintainState: true,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SplitHandle(
              axis: Axis.horizontal,
              thickness: handle,
              line: true,
              onDrag: (dx) => setState(() => _cppWidth = cppWidth - dx),
              onEnd: () {
                final w = cppWidth;
                _cppWidth = null;
                s.updateSettings((st) => st.cppPaneWidth = w);
              },
              onReset: () => s.updateSettings((st) => st.cppPaneWidth = Settings.defaultCppPaneWidth),
            ),
            SizedBox(
              width: cppWidth,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  color: c.surface,
                  child: Row(children: [
                    Text('C++ FROM THE BLOCKS', style: tOverline(c)),
                    const Spacer(),
                    if (p.codeEdited) Btn('Use the blocks again', icon: 'swap', kind: BtnKind.plain, onTap: () => _confirmRebuild(context, s, p)),
                  ]),
                ),
                if (p.codeEdited)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    color: c.surface,
                    child: Text('${p.files.first.name} was edited by hand, so these blocks don\'t change it.',
                        style: tCaption(c, color: c.muted)),
                  ),
                Expanded(
                  child: MonacoEditor(
                    key: _preview,
                    fileKey: '${p.id}/blocks.cpp',
                    text: p.blocklyCode ?? p.generate(),
                    readOnly: true,
                    options: _monacoOptions(s, c),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]);
    });
  }

  /// The strip above the code (CD-01): generated from the blocks, edited by hand, or a C++ project.
  Widget _codeBanner(BuildContext context, AppState s, RC c, Project p, int fi) {
    final fromBlocks = fi == 0 && (p.blockly != null || p.setup.isNotEmpty || p.loop.isNotEmpty);
    final String text;
    final String icon;
    if (fromBlocks && !p.codeEdited) {
      icon = 'blocks';
      text = 'Generated from your blocks. If you type here, this file becomes C++ and the blocks stop changing it.';
    } else if (fromBlocks) {
      icon = 'pencil';
      text = 'You edited this file, so the blocks no longer change it.';
    } else {
      icon = 'code';
      text = 'C++ project. Ctrl+Space shows suggestions; $kMod+F finds; $kMod+. offers quick fixes.';
    }
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(color: c.sunk, border: Border(bottom: BorderSide(color: c.line2))),
      child: Row(children: [
        RcIcon(icon, size: 16, color: c.ink),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: tLabel(c, w: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (fromBlocks && p.codeEdited) ...[
          const SizedBox(width: 8),
          Btn('Rebuild from blocks', icon: 'repeat', small: true, height: 28, onTap: () => _confirmRebuild(context, s, p)),
        ],
      ]),
    );
  }

  /// “Rebuild the code from your blocks?” (CD-02).
  void _confirmRebuild(BuildContext context, AppState s, Project p) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (dctx) {
        void go() {
          Navigator.of(dctx).pop();
          s.rebuildFromBlocks();
        }

        return DialogFrame(
          title: 'Rebuild the code from your blocks?',
          subtitle: 'Your typed changes in ${p.files.first.name} are replaced by the code the blocks generate.',
          onSubmit: go,
          actions: [
            Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(dctx).pop()),
            Btn('Rebuild', icon: 'repeat', kind: BtnKind.primary, onTap: go),
          ],
        );
      },
    );
  }

  /// “Delete all N blocks?” (BK-10). Undo brings them back.
  void _confirmClear(BuildContext context, AppState s, Project p) {
    final n = p.blocklyCount ?? p.setup.length + p.loop.length;
    if (n == 0) return s.showToast('There are no blocks to delete', info: true);
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (dctx) {
        void go() {
          Navigator.of(dctx).pop();
          if (kWebEditors) {
            _blockly.currentState?.clear();
            s.showToast('All blocks deleted', body: 'Undo ($kMod+Z) brings them back.', info: true);
          } else {
            s.clearBlocks();
          }
        }

        return DialogFrame(
          title: 'Delete all $n block${n == 1 ? '' : 's'}?',
          subtitle: 'Undo ($kMod+Z) brings them back.',
          onSubmit: go,
          actions: [
            Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(dctx).pop()),
            Btn('Delete', icon: 'trash', kind: BtnKind.primary, onTap: go),
          ],
        );
      },
    );
  }

  /// “New tab” (CD-03): a .ino, .h or .cpp file in this sketch.
  void _newTab(BuildContext context, AppState s, Project p) {
    showDialog<void>(context: context, barrierColor: const Color(0x521B2A41), builder: (_) => _NewTabDialog(s: s, p: p));
  }

  Widget _monacoFor(AppState s, RC c, Project p, int fi) {
    final f = p.files[fi];
    return MonacoEditor(
      key: _monaco,
      fileKey: '${p.id}/${f.name}',
      text: f.content,
      options: _monacoOptions(s, c),
      problems: [
        for (final e in s.problems)
          if (e.file == f.name) {'line': e.line, 'column': e.column, 'message': e.msg, 'severity': e.severity}
      ],
      onChange: (text) {
        final handEdit = !p.codeEdited && s.file == 0;
        s.editCode(text);
        if (handEdit) s.showToast('Code edited by hand', body: 'The blocks will stop updating it.', info: true);
      },
      onCursor: (line, column) => s.setCursor('Ln $line, Col $column'),
      onExplain: (line) => _explainLine(s, f.name, line),
    );
  }

  /// A click on a problem (AppState.gotoProblem) moves Monaco's cursor there once it is showing.
  void _takeGotoLine(AppState s, Project p) {
    final line = s.gotoLine;
    if (line == null || p.mode != 'code') return;
    s.gotoLine = null;
    void go() => _monaco.currentState?.reveal(line);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      go();
      Future<void>.delayed(const Duration(milliseconds: 800), go); // in case the editor was still loading
    });
  }
}

class ConsolePanel extends StatelessWidget {
  const ConsolePanel({super.key, this.boardTab = false});
  final bool boardTab;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;
    final t = s.panelTab;

    Widget tab(String k, String label) {
      final on = t == k;
      return Hover(
        onTap: () => s.setPanelTab(k),
        builder: (context, h) => Container(
          height: 40,
          padding: const EdgeInsets.only(left: 10, right: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? c.ink : Colors.transparent, width: 2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: tLabel(c, color: on ? c.ink : c.faint, w: on ? FontWeight.w600 : FontWeight.w500)),
            if (k == 'problems' && s.problems.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(color: c.sunk, borderRadius: BorderRadius.circular(4)),
                child: Text('${s.problems.length}', style: tCaption(c, color: c.ink, w: FontWeight.w500)),
              ),
            ],
          ]),
        ),
      );
    }

    Widget body() {
      switch (t) {
        case 'serial':
          return const Column(children: [Expanded(child: SerialLog()), SendRow(hint: 'Send a message to the board')]);
        case 'output':
          return const OutputLog();
        case 'board':
          return SingleChildScrollView(child: BoardCard(boardId: s.cur?.board ?? s.board));
        default:
          if (s.problems.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                RcIcon('check', size: 15, color: c.muted),
                const SizedBox(width: 8),
                Text('No problems in this sketch.', style: tBody(c, size: 13, color: c.muted)),
              ]),
            );
          }
          return ListView(padding: const EdgeInsets.all(8), children: [
            for (final e in s.problems)
              Hover(
                onTap: () => s.gotoProblem(e),
                builder: (context, h) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(color: h ? c.raised : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 2), child: RcIcon(e.isError ? 'alert' : 'info', size: 15, color: e.isError ? c.err : c.muted)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.msg, style: tBody(c, size: 13, height: 18 / 13))),
                    const SizedBox(width: 10),
                    CogExplainButton(problem: e),
                    const SizedBox(width: 10),
                    Text('${e.file}:${e.line}', style: tMono(c, size: 12, color: c.muted, height: 18 / 12)),
                  ]),
                ),
              ),
          ]);
      }
    }

    return RcCard(
      child: Column(children: [
        Container(
          height: 40,
          padding: const EdgeInsets.only(left: 8, right: 8),
          decoration: BoxDecoration(border: s.panelOpen ? Border(bottom: BorderSide(color: c.line2)) : null),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  tab('serial', phone ? 'Serial' : 'Serial Monitor'),
                  tab('output', 'Output'),
                  tab('problems', 'Problems'),
                  if (boardTab) tab('board', 'Board'),
                ]),
              ),
            ),
            if (s.panelOpen && t == 'serial') ...[
              if (!phone)
                RcSelect<int>(
                  value: s.baud,
                  width: 128,
                  height: 28,
                  label: 'Baud rate',
                  items: const [(9600, '9600 baud'), (57600, '57600 baud'), (115200, '115200 baud'), (230400, '230400 baud')],
                  onChanged: s.setBaud,
                ),
              const SizedBox(width: 4),
              IconBtn('trash', onTap: s.clearLog, tip: 'Clear serial output'),
            ],
            if (s.panelOpen && t == 'output') IconBtn('trash', onTap: s.clearOutput, tip: 'Clear output'),
            if (s.panelOpen && t == 'problems') IconBtn('trash', onTap: s.clearProblems, tip: 'Clear problems'),
            Transform.rotate(
              angle: s.panelOpen ? 0 : 3.14159,
              child: IconBtn('chev', onTap: s.togglePanel, tip: s.panelOpen ? 'Collapse console' : 'Expand console'),
            ),
          ]),
        ),
        if (s.panelOpen) Expanded(child: body()),
      ]),
    );
  }
}

/// The board card beside the console (or in its Board tab): the preview board while the port is the
/// simulator, else the real board's details and USB status.
class BoardCard extends StatelessWidget {
  const BoardCard({super.key, required this.boardId});
  final String boardId;
  @override
  Widget build(BuildContext context) =>
      AppScope.of(context).onUsb ? BoardSummary(boardId: boardId, extra: const _UsbBoardStatus()) : const LiveBoard();
}

/// The preview board (the design's Preview Board card): the LED (on the RoboCore V2 the RGB LED) and the USER
/// button, and the live readings: motors, servo, and on the V2 the sonar, line sensor, tilt and battery, each of
/// which a click can hold at a value (PB-01).
class LiveBoard extends StatefulWidget {
  const LiveBoard({super.key});
  @override
  State<LiveBoard> createState() => _LiveBoardState();
}

class _LiveBoardState extends State<LiveBoard> {
  Timer? _tick;
  SimSensor? _editing;

  @override
  void initState() {
    super.initState();
    // The sensors drift while a sketch runs without telling anyone, so look again a few times a second.
    _tick = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted && AppScope.read(context).sim.running) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final sim = s.sim;
    final b = kBoards[s.cur?.board ?? s.board]!;
    final v2 = b.id == 'v2';
    return ListenableBuilder(
      listenable: sim,
      builder: (context, _) {
        final running = sim.running;
        // The RoboCore V2 has no plain LED: LED_BUILTIN is the RGB LED.
        final rgb = sim.rgbColor ?? const [0, 0, 0];
        final Color? lit = !running
            ? null
            : v2
                ? (rgb[0] + rgb[1] + rgb[2] > 0 ? Color.fromARGB(255, rgb[0], rgb[1], rgb[2]) : null)
                : (sim.led != 0 ? kBrand : null);
        final white = lit != null && rgb[0] == rgb[1] && rgb[1] == rgb[2];
        // A white LED would read as off on the cream page: the design draws a lit LED in the box yellow.
        final glow = white ? kBrand : lit;
        final io = <String>[
          if (!v2 && (sim.motorSpeeds[0] != 0 || sim.motorSpeeds[1] != 0)) 'motors ${sim.motorSpeeds[0]} / ${sim.motorSpeeds[1]}',
          if (!v2 && sim.servoAngle != null) 'servo ${sim.servoAngle}°',
          if (sim.toneHz != null) 'tone ${sim.toneHz} Hz',
          for (final e in sim.pins.entries) 'pin ${e.key} ${e.value != 0 ? 'HIGH' : 'LOW'}',
        ];
        final state = running ? 'Running' : (s.lastRun != null ? 'Stopped' : 'Simulator');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
            child: Row(children: [
              Expanded(child: Text('PREVIEW BOARD', style: tH2(c), overflow: TextOverflow.ellipsis)),
              Tooltip(
                message: running ? 'Running ${sim.name}. Stop is in the top bar.' : 'Upload runs the sketch here.',
                child: Badge2(state, bg: running ? kNavy : null, fg: running ? kCream : null),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 64,
                child: Column(children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: glow ?? c.sunk,
                      shape: BoxShape.circle,
                      border: Border.all(color: kNavy, width: 1.5),
                      boxShadow: glow == null ? null : [BoxShadow(color: glow.withValues(alpha: .6), blurRadius: 16, spreadRadius: 3)],
                    ),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: lit == null ? c.line2 : Colors.white.withValues(alpha: .85),
                        shape: BoxShape.circle,
                        border: Border.all(color: kNavy, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${v2 ? 'RGB' : 'LED'} · ${lit == null ? 'off' : (v2 && white ? 'white' : 'on')}',
                      style: tCaption(c, color: c.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  _UserButton(label: v2 ? 'USER' : 'BUTTON'),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (v2) ...[
                    _reading(c, 'Motors', 'L ${sim.motorSpeeds[0]} % · R ${sim.motorSpeeds[1]} %'),
                    _reading(c, 'Servo 1', sim.servoAngle == null ? '—' : '${sim.servoAngle}°'),
                    for (final k in SimSensor.values) ..._sensor(c, sim, k),
                  ],
                  if (!v2 && sim.readsDistance) ..._sensor(c, sim, SimSensor.sonar),
                  if (io.isNotEmpty || !v2)
                    Padding(
                      padding: EdgeInsets.only(top: v2 ? 4 : 0),
                      child: Text(io.isEmpty ? 'Nothing else active' : io.join(' · '),
                          style: tMono(c, size: 11, color: c.faint, height: 16 / 11), maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  // A reading: name, then the value (bold while held at a value).
  Widget _reading(RC c, String k, String v, {bool held = false}) => SizedBox(
        height: 20,
        child: Row(children: [
          SizedBox(width: 50, child: Text(k, style: tCaption(c, color: c.faint), maxLines: 1)),
          Expanded(
            child: Text(v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tMono(c, size: 11, height: 16 / 11, color: c.ink, w: held ? FontWeight.w800 : FontWeight.w400)),
          ),
        ]),
      );

  static const _names = {SimSensor.sonar: 'Sonar', SimSensor.line: 'Line', SimSensor.tilt: 'Tilt', SimSensor.battery: 'Battery'};

  // Each sensor's slider: range, steps and how the value reads.
  static (double, double, int, String Function(double)) _range(SimSensor k) => switch (k) {
        SimSensor.sonar => (2, 200, 198, (v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} cm'),
        SimSensor.line => (-1, 1, 40, _lineText),
        SimSensor.tilt => (0, 90, 180, (v) => '${v.toStringAsFixed(1)}°'),
        SimSensor.battery => (3, 4.2, 120, (v) => '${v.toStringAsFixed(2)} V'),
      };

  // The line position as the three sensors see it: how dark it is under the left, centre and right one.
  static String _lineText(double pos) {
    String f(num v) => v.clamp(0, 1).toStringAsFixed(1);
    return 'L ${f(-pos)} C ${f(1 - pos.abs())} R ${f(pos)}';
  }

  List<Widget> _sensor(RC c, SimBoard sim, SimSensor k) {
    final (lo, hi, steps, text) = _range(k);
    final held = sim.held.containsKey(k);
    final v = sim.reading(k).clamp(lo, hi).toDouble();
    final open = _editing == k;
    final name = _names[k]!;
    return [
      Hover(
        onTap: () => setState(() => _editing = open ? null : k),
        tooltip: open
            ? null
            : held
                ? 'Held at ${text(v)}. Click to change it.'
                : 'Click to set what the ${name.toLowerCase()} reads',
        builder: (context, h) => Container(
          decoration: BoxDecoration(color: h || open ? c.sunk : Colors.transparent, borderRadius: BorderRadius.circular(4)),
          child: _reading(c, name, text(v), held: held),
        ),
      ),
      if (open)
        Container(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
          decoration: BoxDecoration(color: c.sunk, borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: c.ink,
                  inactiveTrackColor: c.line,
                  thumbColor: c.ink,
                  overlayColor: c.ink.withValues(alpha: .08),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: SizedBox(
                  height: 26,
                  child: Slider(
                    value: v,
                    min: lo,
                    max: hi,
                    divisions: steps,
                    semanticFormatterCallback: text,
                    onChanged: (x) => sim.hold(k, x),
                  ),
                ),
              ),
            ),
            Btn('Auto', kind: BtnKind.plain, small: true, tooltip: 'Back to the simulated reading', onTap: held ? () => sim.hold(k, null) : null),
          ]),
        ),
    ];
  }
}

/// The editor's board card while the real board is on USB.
class _UsbBoardStatus extends StatelessWidget {
  const _UsbBoardStatus();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final pct = s.uploadPct;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          LinkDot(on: s.usbOpen, size: 7),
          const SizedBox(width: 7),
          Expanded(
            child: Text(s.usbOpen ? 'Real board on ${s.usbName}' : 'Real board not connected',
                style: tCaption(c, color: s.usbOpen ? c.ok : c.muted, w: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 6),
        if (pct != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: c.sunk, color: kBrand),
          ),
          const SizedBox(height: 6),
          Text('Uploading $pct %', style: tCaption(c)),
        ] else
          Text(
            s.usbOpen
                ? '${s.usbLabel ?? 'USB'} · Upload compiles on the server and flashes it here.'
                : 'Plug in the RoboCore and press Connect.',
            style: tCaption(c),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 8),
        Row(children: [
          if (s.usbOpen)
            Btn('Reset board', kind: BtnKind.plain, small: true, onTap: s.busy == null ? s.resetUsbBoard : null)
          else
            Btn('Connect', kind: BtnKind.primary, small: true, onTap: s.connectUsb),
          const SizedBox(width: 8),
          if (!s.hasServer)
            Expanded(child: Text('Set a compile server in Settings', style: tCaption(c, color: c.err, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    );
  }
}

class _UserButton extends StatelessWidget {
  const _UserButton({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final sim = AppScope.read(context).sim;
    final c = RC.of(context);
    // The design's USER button: an outlined pill, filled with ink only while it is held.
    return Tooltip(
      message: 'Hold to press. Pulls input pins LOW.',
      child: Listener(
        onPointerDown: (_) => sim.setUser(true),
        onPointerUp: (_) => sim.setUser(false),
        onPointerCancel: (_) => sim.setUser(false),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            height: 26,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: sim.user ? c.ink : null,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: c.ink),
            ),
            child: Text(label, style: tBody(c, size: 12, w: FontWeight.w500, height: 16 / 12, color: sim.user ? c.bg : c.ink)),
          ),
        ),
      ),
    );
  }
}

class _NewTabDialog extends StatefulWidget {
  const _NewTabDialog({required this.s, required this.p});
  final AppState s;
  final Project p;
  @override
  State<_NewTabDialog> createState() => _NewTabDialogState();
}

class _NewTabDialogState extends State<_NewTabDialog> {
  final _name = TextEditingController();
  String? error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _add() {
    final e = widget.s.validateFileName(widget.p, _name.text);
    if (e != null) {
      setState(() => error = e);
      return;
    }
    Navigator.of(context).pop();
    widget.s.addFile(widget.p, _name.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return DialogFrame(
      title: 'New tab',
      subtitle: 'Add a .ino, .h or .cpp file to this sketch.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FieldLabel('File name'),
        RcInput(
          controller: _name,
          hint: 'motors.h',
          height: 36,
          fontSize: 14,
          autofocus: true,
          error: error != null,
          onChanged: (_) => setState(() => error = null),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 6),
        Text(error ?? 'Letters, numbers, _ or -, then .ino, .h, .hpp, .c or .cpp',
            style: tCaption(c, color: error != null ? c.err : c.faint, w: error != null ? FontWeight.w600 : FontWeight.w400)),
      ]),
      actions: [
        Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(context).pop()),
        Btn('Add tab', icon: 'plus', kind: BtnKind.primary, onTap: _add),
      ],
    );
  }
}
