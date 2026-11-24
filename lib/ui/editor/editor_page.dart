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
import 'block_picture.dart';
import 'blocks_view.dart';
import 'code_view.dart';
import 'web_editors.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TickerProviderStateMixin {
  bool _canUndo = false, _canRedo = false; // Blockly's undo stack (BK-09)

  // The parts that slide open and closed beside the editors (_Slide): the Serial Monitor drawer under them, the
  // "C++ from the blocks" pane beside the blocks and Cog's column on the right.
  late final _drawer = _Slide(this, open: AppScope.read(context).panelOpen);
  late final _cpp = _Slide(this, open: false);

  late final _cog = _Slide(this, open: AppScope.read(context).cog.open, inMs: 260);

  /// The editor's first frame: the C++ pane is put away then (initState), so it is not seen to slide shut.
  bool _firstFrame = true;
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
    // The blocks open with the room to drag them: the "C++ from the blocks" pane starts closed each time the editor
    // opens, and only its button (or View › C++ from the blocks) opens it.
    final s = AppScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (s.settings.showCpp) s.updateSettings((st) => st.showCpp = false);
      _firstFrame = false;
    });
    // Cog hands blocks and code to the Blockly and Monaco editors (the Flutter editors of the other apps take none).
    if (kWebEditors) {
      cogAddBlocks = _addBlocks;
      cogInsertCode = _insertCode;
      cogPictureBlocks = _pictureBlocks;
    }
  }

  void _addBlocks(String json) => _blockly.currentState?.add(json);
  void _insertCode(String text) => _monaco.currentState?.insert(text);
  Future<BlockPicture?> _pictureBlocks(String json, double ratio) => _blockly.currentState?.picture(json, ratio) ?? Future.value(null);

  @override
  void dispose() {
    if (editorMenuCommand == _menuCommand) editorMenuCommand = null;
    if (cogAddBlocks == _addBlocks) cogAddBlocks = null;
    if (cogInsertCode == _insertCode) cogInsertCode = null;
    if (cogPictureBlocks == _pictureBlocks) cogPictureBlocks = null;
    _drawer.dispose();
    _cpp.dispose();
    _cog.dispose();
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

    final openTabs = [for (var i = 0; i < p.files.length; i++) if (!s.closedTabs.contains(i)) i];
    // With the web editors the code keeps its tabs while the blocks show (they wait in the hidden code slot).
    final tabs = p.mode == 'code' || kWebEditors
        ? Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final i in openTabs)
                  AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    height: 36,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.only(left: 10, right: 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: i == fi ? c.ink : c.ink.withValues(alpha: 0), width: 2)),
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

    // Code: the file tabs and Find above the code. Blocks: nothing, the canvas starts at the top (its view tools
    // float bottom left, see _ViewTools). With the web editors the bar is part of the code's slot, so switching
    // never changes either editor's size (a WebView that grows shows a blank strip until WebKit redraws it).
    final Widget toolbar = p.mode == 'code' || kWebEditors
        ? Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              if (tabs != null) tabs,
              const Spacer(),
              IconBtn('search', onTap: () => kWebEditors ? _monaco.currentState?.find() : _active?.currentState?.toggleFind(), tip: 'Find'),
            ]),
          )
        : const SizedBox.shrink();

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
      // Both editors stay loaded while the project is open, so Blocks ↔ C++ is quick and Blockly keeps its
      // undo history; the hidden one is only not painted (its iframe stays in the page). The switch crossfades.
      main = _ModeFade(
        index: p.mode == 'blocks' ? 0 : 1,
        children: [
          _blocklyArea(s, c, p, width),
          // The tab bar and the banner always take this slot, so Monaco's frame never moves (moving it would
          // reload it) and keeps one size.
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            toolbar,
            _codeBanner(context, s, c, p, fi),
            Expanded(child: _monacoFor(s, c, p, fi)),
          ]),
        ],
      );
      _takeGotoLine(s, p);
    }

    // The workspace, in its card (the design's Workspace, see _card). The floating controls sit over it; the editor
    // stays the first child of the Stack, so showing or hiding them never moves (and reloads) the Blockly or Monaco frame.
    final blocks = p.mode == 'blocks';
    final workspace = LayoutBuilder(builder: (context, box) {
      // With the C++ pane open beside the blocks, the blocks' view tools stay over the blocks, at their right edge
      // (they follow the divider when it is dragged); the run buttons keep the workspace's right edge.
      // (They move with the pane as it slides open or shut.)
      final (cppFits, cppWidth) = blocks && kWebEditors ? _cppPane(width, box.maxWidth) : (false, 0.0);
      final besideCpp = cppFits ? cppWidth + _cppHandle : 0.0;
      return Stack(children: [
        Positioned.fill(
            child: ColoredBox(color: c.surface, child: kWebEditors ? main : Column(children: [toolbar, Expanded(child: main)]))),
        // Connect is in the editor's top bar (EditorConnectButton), so nothing floats over the top of the code.
        // The view tools: a column on the right edge of the blocks (or the code), above the run buttons, where the
        // block list (which opens on the left) never reaches.
        AnimatedBuilder(
          animation: _cpp.t,
          // In a short window (or with the Serial Monitor tall) the column shrinks to the room above the run buttons
          // instead of running out of the workspace's card at the top.
          child: FrameShield(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: math.max(96, box.maxHeight - (phone ? 104 : 130) - 8)),
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomCenter, child: _viewTools(s, c, p, width)),
            ),
          ),
          builder: (context, tools) => Positioned(
            // centred over the Upload button when nothing is beside the blocks
            right: (phone ? 21 : 33) + besideCpp * _cpp.t.value,
            bottom: phone ? 104 : 130,
            child: tools!,
          ),
        ),
        Positioned(right: 20, bottom: 14, child: FrameShield(child: _RunButtons(compact: phone))),
      ]);
    });
    // Shown only while the drawer is open or on its way, so it is drawn open throughout (closing, it slides away
    // whole instead of emptying first).
    final panel = ConsolePanel(boardTab: !showBoard, open: true);
    final cogBeside = width >= 1000;
    _drawer.follow(s.panelOpen, context);
    _cog.follow(s.cog.open, context);
    _cpp.follow(s.settings.showCpp && !_firstFrame, context);

    final content = LayoutBuilder(builder: (context, box) {
      // The Serial Monitor is a drawer under the workspace, opened from the run buttons (or Ctrl/⌘+J). It keeps
      // 120 px at least and leaves the workspace 200 px at least.
      final maxConsole = (box.maxHeight - 200).clamp(120.0, double.infinity);
      final consoleHeight = (phone ? 220.0 : _consoleHeight ?? s.settings.consoleHeight).clamp(120.0, maxConsole);
      final drawer = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The gap between the workspace and the drawer's cards is the handle that resizes them.
          if (phone)
            const SizedBox(height: _gapPhone)
          else
            SplitHandle(
              axis: Axis.vertical,
              thickness: _gap,
              onDrag: (dy) => setState(() => _consoleHeight = consoleHeight - dy),
              onEnd: () {
                final h = consoleHeight;
                _consoleHeight = null;
                s.updateSettings((st) => st.consoleHeight = h);
              },
              onReset: () => s.updateSettings((st) => st.consoleHeight = Settings.defaultConsoleHeight),
            ),
          SizedBox(
            height: consoleHeight,
            child: showBoard
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _card(c, panel)),
                    const SizedBox(width: _gap),
                    SizedBox(width: 280, child: _card(c, SingleChildScrollView(child: BoardCard(boardId: p.board)))),
                  ])
                : _card(c, panel),
          ),
        ]);
      return Column(children: [
        Expanded(child: _card(c, workspace)),
        // The drawer rises from under the workspace, its tabs first; the workspace above gives way as it comes.
        AnimatedBuilder(
          animation: _drawer.t,
          child: drawer,
          builder: (context, drawer) => !_drawer.shows
              ? const SizedBox.shrink()
              : ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: _drawer.t.value, child: drawer)),
        ),
      ]);
    });

    // The editor stays the first child in the same place whether Cog is open or not, so the
    // Blockly and Monaco frames are never moved (moving them would reload them).
    // Cog slides in from the right: beside the editor its column opens and the editor gives way (steady while it
    // moves, see _Slide); over a narrow editor the panel slides and fades in. Shut, it is kept until it has gone.
    return Stack(children: [
      Positioned.fill(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The cards sit on the window's colour, 12 px from its edges and from each other (the design's Main area).
          Expanded(child: ColoredBox(color: c.bg, child: Padding(padding: EdgeInsets.all(phone ? _gapPhone : _gap), child: content))),
          if (cogBeside)
            AnimatedBuilder(
              animation: _cog.t,
              // (The editor's margin is the gap on its left.)
              child: const Padding(padding: EdgeInsets.fromLTRB(0, _gap, _gap, _gap), child: SizedBox(width: 352, child: CogPanel())),
              builder: (context, cog) => !_cog.shows
                  ? const SizedBox.shrink()
                  : ClipRect(child: Align(alignment: Alignment.centerLeft, widthFactor: _cog.t.value, child: cog)),
            ),
        ]),
      ),
      if (!cogBeside)
        AnimatedBuilder(
          animation: _cog.t,
          child: const FrameShield(child: CogPanel()),
          builder: (context, cog) => !_cog.shows
              ? const SizedBox.shrink()
              : Positioned(
                  top: 12,
                  right: 12,
                  bottom: 12,
                  width: math.min(400, width - 24),
                  child: IgnorePointer(
                    ignoring: !s.cog.open,
                    child: Opacity(
                      opacity: _cog.t.value,
                      child: Transform.translate(offset: Offset(48 * (1 - _cog.t.value), 0), child: cog),
                    ),
                  ),
                ),
        ),
    ]);
  }

  /// A column on the right of the workspace, above the run buttons. Blocks: fit, zoom in, zoom out · undo, redo ·
  /// delete all · the C++ beside the blocks. Code: text size, undo, redo.
  // Beside the blocks: the blocks keep at least 400 px (the toolbox takes ~150), the C++ pane at least 240 px.
  static const _minBlocks = 400.0, _minCpp = 240.0, _cppHandle = 7.0;

  /// The design's spacing: 12 px around the cards and between them (8 on a phone).
  static const _gap = 12.0, _gapPhone = 8.0;

  /// A card of the editor (the design's Workspace, Console and Board info): 10 px corners, a 1 px line, the surface
  /// colour. The line is drawn behind the content, which sits 1 px inside it and is clipped to the corners (the Blockly
  /// and Monaco WebViews too). Never draw over a WebView here: on macOS whatever Flutter paints above a WebView takes
  /// the mouse over its whole bounds, and a line round the card took the whole workspace (blocks could not be dragged,
  /// 2026-11-24).
  static Widget _card(RC c, Widget child) => DecoratedBox(
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: ClipRRect(borderRadius: BorderRadius.circular(9), child: ColoredBox(color: c.surface, child: child)),
        ),
      );

  /// Whether the "C++ from the blocks" pane fits beside the blocks in a workspace [boxWidth] wide, and its width.
  /// (Whether it is open is _cpp's: it slides.)
  (bool, double) _cppPane(double width, double boxWidth) {
    final s = AppScope.read(context);
    final fits = width >= 900 && boxWidth >= _minBlocks + _minCpp + _cppHandle;
    final w = (_cppWidth ?? s.settings.cppPaneWidth).clamp(_minCpp, (boxWidth - _minBlocks - _cppHandle).clamp(_minCpp, double.infinity));
    return (fits, w);
  }

  Widget _viewTools(AppState s, RC c, Project p, double width) {
    final blocks = p.mode == 'blocks';
    final code = _monaco.currentState;
    void font(int size) => s.updateSettings((st) => st.fontSize = size.clamp(10, 24));
    // Short windows (a laptop with the update banner showing) get smaller buttons, so the column clears the toolbar.
    final small = MediaQuery.sizeOf(context).height < 760;
    final size = small ? 34.0 : 40.0;
    Widget sep() => Container(width: 26, height: 1, margin: EdgeInsets.symmetric(vertical: small ? 3 : 4), color: c.line);
    Widget b(String icon, String tip, VoidCallback? onTap, {bool active = false}) =>
        IconBtn(icon, onTap: onTap, tip: tip, size: size, iconSize: small ? 18 : 20, active: active);
    // Blocks has more tools than Code: on a switch the column grows or shrinks from the bottom while the buttons
    // crossfade (kModeSwitch), instead of jumping.
    final still = MediaQuery.disableAnimationsOf(context);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(14), boxShadow: popShadow),
      child: AnimatedSize(
        duration: still ? Duration.zero : kModeSwitch,
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: still ? Duration.zero : kModeSwitch,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.bottomCenter, children: [...previous, if (current != null) current]),
          child: Column(key: ValueKey(blocks), mainAxisSize: MainAxisSize.min, children: blocks
          ? [
              if (kWebEditors) ...[
                // Back to the view a project opens with (the starting size, centred on the blocks), as View › Actual
                // Size does. Zoom to fit enlarged a small program to fill the screen.
                b('fit', 'Back to the starting view ($kMod+0)', () => _blockly.currentState?.resetZoom()),
                b('zin', 'Zoom in ($kMod+=)', () => _blockly.currentState?.zoom(1)),
                b('zout', 'Zoom out ($kMod+−)', () => _blockly.currentState?.zoom(-1)),
                sep(),
              ],
              b('undo', 'Undo ($kMod+Z)', kWebEditors ? (_canUndo ? () => _blockly.currentState?.undo() : null) : s.undo),
              b('redo', 'Redo ($kMod+Shift+Z)', kWebEditors ? (_canRedo ? () => _blockly.currentState?.redo() : null) : s.redo),
              sep(),
              b('trash', 'Delete all blocks', () => _confirmClear(context, s, p)),
              if (kWebEditors && width >= 900)
                b('code', s.settings.showCpp ? 'Hide the C++ from the blocks' : 'Show the C++ from the blocks',
                    () => s.updateSettings((st) => st.showCpp = !st.showCpp),
                    active: s.settings.showCpp),
            ]
          : [
              b('zin', 'Larger text', () => font(s.settings.fontSize + 1)),
              b('zout', 'Smaller text', () => font(s.settings.fontSize - 1)),
              sep(),
              b('undo', 'Undo ($kMod+Z)', kWebEditors ? () => code?.action('undo') : null),
              b('redo', 'Redo ($kMod+Shift+Z)', kWebEditors ? () => code?.action('redo') : null),
            ]),
        ),
      ),
    );
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
        'pinLabels': pinLabels(p.board),
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
      final (fits, cppWidth) = _cppPane(width, box.maxWidth);
      const handle = _cppHandle;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: editor),
        // Hidden, the C++ pane keeps its editor loaded (and takes no room). It slides out from the blocks' right edge
        // (_cpp): its editor keeps its size throughout and is uncovered, the blocks give way (steady meanwhile).
        AnimatedBuilder(
          animation: _cpp.t,
          builder: (context, pane) => Visibility(
            visible: fits && _cpp.shows,
            maintainState: true,
            child: ClipRect(child: Align(alignment: Alignment.centerLeft, widthFactor: _cpp.t.value, child: pane)),
          ),
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
                  // (Shown again after the pane was shut, it holds its page colour until WebKit has drawn it: _Shown.)
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

/// How long Blocks ↔ Code takes: the editors' crossfade, the view tools and the switch's sliding pill (shell.dart).
const kModeSwitch = Duration(milliseconds: 220);

/// A part that slides open (ease out, [inMs]) and shut (ease in, [outMs]) beside the editors: the Serial Monitor
/// drawer, the C++ pane, Cog's column. While any of them moves the editors keep a steady size (as while a divider is
/// dragged, see _Steady in web_editors_native.dart): a WebView resized every frame shows blank strips until WebKit
/// catches up, so they take their new size once, when everything has arrived. No motion when the system asks for less.
class _Slide {
  _Slide(TickerProvider vsync, {required bool open, int inMs = 240, int outMs = 200})
      : _c = AnimationController(
          vsync: vsync,
          duration: Duration(milliseconds: inMs),
          reverseDuration: Duration(milliseconds: outMs),
          value: open ? 1 : 0,
        ) {
    // Shutting eases in and out: it starts gently, so the first frames uncover next to nothing (see follow).
    t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInOutCubic);
    _c.addStatusListener((st) {
      if (st == AnimationStatus.completed || st == AnimationStatus.dismissed) _settled();
    });
  }

  final AnimationController _c;
  Timer? _wait;

  /// 0 shut … 1 open, eased.
  late final CurvedAnimation t;
  bool? _open;
  bool _moving = false;

  /// How many slides are moving: the editors are steady while any is.
  static int _anyMoving = 0;

  /// Whether any of it shows (open, or on its way).
  bool get shows => _c.value > 0;

  /// Follows [open]. The first call takes it as it is (the editor opens with the part already open or shut).
  void follow(bool open, BuildContext context) {
    if (_open == open) return;
    final first = _open == null;
    _open = open;
    if (first) {
      _c.value = open ? 1 : 0;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = open ? 1 : 0;
      return;
    }
    if (!_moving) {
      _moving = true;
      if (_anyMoving++ == 0) setEditorFramesInteractive(false);
    }
    _wait?.cancel();
    if (open) {
      _c.forward();
    } else {
      // Shutting uncovers editor that was hidden under the part. The editors have just been made steady (as big as the
      // window), and WebKit paints that new room a frame or three later: uncovered sooner it shows black (seen in a
      // frame-by-frame recording of the Mac app, 2026-11-23). So the part waits for the paint, then moves.
      _wait = Timer(const Duration(milliseconds: 50), () {
        if (_open == false) _c.reverse();
      });
    }
  }

  void _settled() {
    if (!_moving) return;
    _moving = false;
    if (--_anyMoving == 0) setEditorFramesInteractive(true);
  }

  void dispose() {
    _wait?.cancel();
    _settled();
    t.dispose();
    _c.dispose();
  }
}

/// Blocks ↔ Code as a crossfade. Both editors stay in the tree throughout (each WebView keeps its page and size);
/// when still, only the shown one is painted, as in an IndexedStack. While switching, the lower editor stays fully
/// painted and the upper one fades over it (in, or out), so the page never dims between the two; the editor that
/// comes in slides the last few points from the side of the switch it was picked on (Blocks left, Code right).
/// macOS fades and moves the WebViews themselves (platform-view opacity and transform), the web app its iframes.
/// No motion when the system asks for less.
class _ModeFade extends StatefulWidget {
  const _ModeFade({required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<_ModeFade> createState() => _ModeFadeState();
}

class _ModeFadeState extends State<_ModeFade> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: kModeSwitch, value: 1);
  late int _from = widget.index;
  static const _slide = 16.0;

  @override
  void didUpdateWidget(_ModeFade old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    // A switch back while one is under way starts from the editor that was coming in.
    _from = old.index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = 1;
    } else {
      _t.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final to = widget.index;
          final moving = _t.value < 1 && _from != to;
          final v = Curves.easeOutCubic.transform(_t.value);
          final upper = math.max(_from, to);
          final dir = to > _from ? 1.0 : -1.0;
          return Stack(fit: StackFit.expand, children: [
            for (var i = 0; i < widget.children.length; i++)
              Offstage(
                // The same widgets in every state, so no editor is rebuilt (and no WebView reloaded) by a switch.
                offstage: !(i == to || (moving && i == _from)),
                child: IgnorePointer(
                  ignoring: i != to,
                  child: Opacity(
                    opacity: !moving || i != upper ? 1 : (i == to ? v : 1 - v),
                    child: Transform.translate(
                      offset: Offset(moving && i == to ? dir * _slide * (1 - v) : 0, 0),
                      child: widget.children[i],
                    ),
                  ),
                ),
              ),
          ]);
        },
      );
}

class ConsolePanel extends StatelessWidget {
  const ConsolePanel({super.key, this.boardTab = false, this.open});
  final bool boardTab;

  /// Drawn open whatever AppState.panelOpen says (the drawer it sits in is closing); null: as panelOpen says.
  final bool? open;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;
    final t = s.panelTab;
    final shown = open ?? s.panelOpen;

    Widget tab(String k, String label) {
      final on = t == k;
      return Hover(
        onTap: () => s.setPanelTab(k),
        // The underline fades over to the picked tab.
        builder: (context, h) => AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.only(left: 10, right: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? c.ink : c.ink.withValues(alpha: 0), width: 2))),
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
          // No Connect of its own here: the editor's one Connect is in its top bar.
          return const Column(children: [Expanded(child: SerialLog(connect: false)), SendRow(hint: 'Send a message to the board')]);
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

    // The card around it (the design's Console: corners, line) is the editor's (_EditorPageState._card), 12 px from
    // the window's edges, the workspace and the board card, so no corner meets an edge.
    return ColoredBox(
      color: c.surface,
      child: Column(children: [
        Container(
          height: 40,
          padding: const EdgeInsets.only(left: 8, right: 8),
          decoration: BoxDecoration(border: shown ? Border(bottom: BorderSide(color: c.line2)) : null),
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
            if (shown && t == 'serial') ...[
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
            if (shown && t == 'output') IconBtn('trash', onTap: s.clearOutput, tip: 'Clear output'),
            if (shown && t == 'problems') IconBtn('trash', onTap: s.clearProblems, tip: 'Clear problems'),
            Transform.rotate(
              angle: shown ? 0 : 3.14159,
              child: IconBtn('chev', onTap: s.togglePanel, tip: shown ? 'Collapse console' : 'Expand console'),
            ),
          ]),
        ),
        if (shown) Expanded(child: body()),
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
          LinkDot(level: s.usbOpen ? 'live' : (s.detectedBoard != null ? 'waiting' : 'off'), size: 7),
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
                // No Connect button here: the editor's one Connect is in its top bar.
                : 'Plug in the RoboCore and press Connect at the top.',
            style: tCaption(c),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (s.usbOpen || !s.hasServer) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (s.usbOpen) ...[
              Btn('Reset board', kind: BtnKind.plain, small: true, onTap: s.busy == null ? s.resetUsbBoard : null),
              const SizedBox(width: 8),
            ],
            if (!s.hasServer)
              Expanded(child: Text('Set a compile server in Settings', style: tCaption(c, color: c.err, w: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          ]),
        ],
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
              // Pressed, ink; otherwise the soft brandSoft fill of the design's Secondary buttons.
              color: sim.user ? c.ink : c.brandSoft,
              borderRadius: BorderRadius.circular(13),
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

/// The editor's one Connect, in its top bar beside the board: navy with the yellow plug (the bar itself is yellow),
/// "Connected" with a green dot once connected; [compact] (a narrow window) shows the plug alone. Not connected, it
/// connects (in the Windows app only while a board is plugged in); connected, it disconnects.
class EditorConnectButton extends StatelessWidget {
  const EditorConnectButton({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final on = s.linked;
    final found = s.onUsb && s.detectedBoard != null;
    final canConnect = !s.onUsb || s.canConnectUsb;
    final label = on ? 'Connected' : (found ? 'Connect board' : 'Connect');
    return Hover(
      onTap: on ? s.disconnect : (canConnect ? s.connect : null),
      tooltip: on
          ? 'Disconnect ${s.onUsb ? (s.usbLabel ?? 'the board') : 'the preview board'}'
          : (canConnect ? 'Connect the board' : 'Plug in the ${kBoards[s.board]!.name} to connect it'),
      radius: 8,
      builder: (context, h) => Opacity(
        opacity: on || canConnect ? 1 : .55,
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 14),
          decoration: BoxDecoration(
            // Connected: white like the board chip beside it; not yet: navy like Home's New project.
            color: on ? Colors.white : (h ? const Color(0xFF2A3D5A) : kNavy),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              RcIcon('plug', size: 18, color: on ? kNavy : kBrand),
              if (on)
                Positioned(
                  right: -4,
                  bottom: -3,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: c.ok, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
            ]),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: on ? kNavy : Colors.white)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Bottom right of the workspace: Serial Monitor, Verify, Stop and the big Upload button.
class _RunButtons extends StatefulWidget {
  const _RunButtons({this.compact = false});
  final bool compact;

  @override
  State<_RunButtons> createState() => _RunButtonsState();
}

class _RunButtonsState extends State<_RunButtons> {
  // Upload's motion: a ring that turns while the sketch is built, fills with the upload's progress, and when the
  // upload has gone well closes and turns the arrow into a tick for a moment (AppState.uploadsDone).
  int? _done;
  bool _tick = false;
  Timer? _untick;

  void _watch(AppState s) {
    if (_done == s.uploadsDone) return;
    final first = _done == null;
    _done = s.uploadsDone;
    if (first) return;
    _tick = true;
    _untick?.cancel();
    _untick = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _tick = false);
    });
  }

  @override
  void dispose() {
    _untick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final s = AppScope.of(context);
    final c = RC.of(context);
    final uploading = s.busy == 'upload';
    _watch(s);
    if (uploading) _tick = false;
    final still = MediaQuery.disableAnimationsOf(context);
    // Serial, Verify and Stop are one size, Upload the big one. Every circle is centred on one line (a slot as tall
    // as Upload) and every label sits on one line under them, so the row lines up whatever the sizes.
    final small = compact ? 44.0 : 52.0, big = compact ? 64.0 : 76.0;

    Widget round(
      String label, {
      required double size,
      required Widget icon,
      required Color bg,
      Color? hover,
      VoidCallback? onTap,
      String? tip,
      Border? border,
      Widget? ring,
    }) =>
        Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: big,
            child: Center(
              child: Hover(
                onTap: onTap,
                tooltip: tip,
                radius: 999,
                builder: (context, h) => SizedBox(
                  width: size,
                  height: size,
                  child: Stack(alignment: Alignment.center, children: [
                    // The circle stays solid when the button can't be pressed (a faded circle vanished into the
                    // workspace); only its icon fades.
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: h && onTap != null ? (hover ?? bg) : bg,
                        shape: BoxShape.circle,
                        border: border,
                        boxShadow: const [BoxShadow(color: Color(0x241B2A41), blurRadius: 14, offset: Offset(0, 5))],
                      ),
                    ),
                    if (ring != null) SizedBox(width: size - 6, height: size - 6, child: ring),
                    // (Upload's arrow stays bright while it uploads: the ring says it is busy.)
                    Opacity(opacity: onTap == null && !(ring != null && uploading) ? .4 : 1, child: icon),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // The label alone, with no pill behind it (the pale pill read as a faint white edge).
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(label, style: tCaption(c, color: c.ink, w: FontWeight.w600)),
          ),
        ]);

    return ListenableBuilder(
      listenable: s.sim,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        round('Serial',
            size: small,
            bg: s.panelOpen ? c.brandSoft : c.raised,
            border: s.panelOpen ? Border.all(color: c.ink, width: 2) : Border.all(color: c.line),
            icon: RcIcon('term', size: 22, color: c.ink),
            tip: s.panelOpen ? 'Hide the Serial Monitor ($kMod+J)' : 'Show the Serial Monitor ($kMod+J)',
            onTap: s.togglePanel),
        SizedBox(width: compact ? 8 : 12),
        round(s.busy == 'verify' ? 'Verifying…' : 'Verify',
            size: small,
            bg: c.raised,
            border: Border.all(color: c.line),
            icon: s.busy == 'verify' ? Spinner(size: 20, color: c.ink) : RcIcon('check', size: 24, color: c.ink),
            tip: 'Verify ($kMod+R)',
            onTap: s.busy == null ? s.verify : null),
        SizedBox(width: compact ? 8 : 12),
        round('Stop',
            size: small,
            bg: c.raised,
            border: Border.all(color: c.line),
            icon: RcIcon('stop', size: 22, color: c.ink),
            tip: uploading ? 'Cancel the upload' : (s.busy == 'verify' ? 'Cancel Verify' : 'Stop the sketch'),
            onTap: s.canStop ? s.stop : null),
        SizedBox(width: compact ? 8 : 12),
        round(uploading ? (s.uploadPct == null ? 'Uploading…' : 'Uploading ${s.uploadPct} %') : (_tick ? 'Uploaded' : 'Upload'),
            size: big,
            bg: kNavy,
            hover: kNavyHover,
            // The arrow stays while the ring works; done, it turns into a tick (a small bounce) and back.
            icon: AnimatedSwitcher(
              duration: still ? Duration.zero : const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: child)),
              child: _tick
                  ? const RcIcon('check', key: ValueKey('tick'), size: 32, color: kBrand)
                  : const RcIcon('arrow', key: ValueKey('arrow'), size: 30, color: kBrand),
            ),
            tip: 'Upload ($kMod+U)',
            ring: AnimatedOpacity(
              opacity: uploading || _tick ? 1 : 0,
              duration: still ? Duration.zero : const Duration(milliseconds: 300),
              child: uploading && s.uploadPct == null
                  // Building (or the preview board's quick upload): no amount yet, so the ring turns.
                  ? const CircularProgressIndicator(strokeWidth: 4, color: kBrand, backgroundColor: kNavyHover, strokeCap: StrokeCap.round)
                  // Writing: the ring follows the percentage smoothly; done, it closes (from empty, after the preview
                  // board's turning ring) and fades.
                  : TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _tick || !uploading ? 1 : s.uploadPct! / 100),
                      duration: still ? Duration.zero : const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => CircularProgressIndicator(
                          value: v, strokeWidth: 4, color: kBrand, backgroundColor: kNavyHover, strokeCap: StrokeCap.round),
                    ),
            ),
            onTap: s.busy == null ? s.upload : null),
      ]),
    );
  }
}
