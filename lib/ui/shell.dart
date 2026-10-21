// App chrome: top bar, sidebar, status bar, board menu, search, toasts, shortcuts.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/catalog.dart';
import '../state/app_state.dart';
import '../state/models.dart';
import '../theme.dart';
import 'account.dart';
import 'app_scope.dart';
import 'dialogs.dart';
import 'editor/editor_page.dart';
import 'editor/web_editors.dart' show setEditorShortcutHandler;
import 'pages/board_page.dart';
import 'pages/examples_page.dart';
import 'pages/home_page.dart';
import 'pages/libraries_page.dart';
import 'pages/projects_page.dart';
import 'pages/serial_page.dart';
import 'pages/settings_page.dart';
import 'pages/welcome_page.dart';
import 'cog/cog_panel.dart' show CogButton;
import 'widgets/brand.dart';
import 'widgets/common.dart';
import 'widgets/menu.dart';
import 'widgets/popover.dart';

const kPhone = 760.0;

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The same shortcuts, typed inside Blockly or Monaco (their iframes keep the keys from Flutter).
    final s = AppScope.of(context);
    setEditorShortcutHandler((action) {
      switch (action) {
        case 'save':
          _save(s);
        case 'verify':
          _verify(s);
        case 'upload':
          _upload(s);
        case 'cog':
          _cog(s);
        case 'sidebar':
          s.toggleSidebar();
        case 'console':
          _console(s);
      }
    });
  }

  @override
  void dispose() {
    setEditorShortcutHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final phone = w < kPhone;
    // First start on this device: ask who is using it before anything else.
    if (s.needsProfile) return const WelcomePage();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _save(s),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _save(s),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => _verify(s),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () => _verify(s),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _upload(s),
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _upload(s),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _cog(s),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _cog(s),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): s.toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): s.toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () => _console(s),
        const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): () => _console(s),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _scaffold,
          backgroundColor: c.bg,
          drawer: phone
              ? Drawer(
                  backgroundColor: c.bg,
                  width: 260,
                  shape: const RoundedRectangleBorder(),
                  child: SafeArea(child: SideBar(collapsed: false, onNavigate: () => _scaffold.currentState?.closeDrawer())),
                )
              : null,
          body: Stack(
            children: [
              Column(
                children: [
                  TopBar(phone: phone, onMenu: () => _scaffold.currentState?.openDrawer()),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!phone) SideBar(collapsed: s.sideCollapsed),
                        Expanded(child: _pages(s, phone)),
                      ],
                    ),
                  ),
                  StatusBar(phone: phone),
                ],
              ),
              if (s.toast != null)
                Positioned(
                  left: phone ? 0 : null,
                  right: phone ? 0 : 24,
                  bottom: phone ? 44 : 52,
                  child: phone ? Center(child: _Toast(text: s.toast!, error: s.toastError)) : _Toast(text: s.toast!, error: s.toastError),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _save(AppState s) {
    final p = s.cur;
    if (s.view == Screen.editor && p != null) {
      s.saveNow(p);
      s.showToast('Saved.');
    }
  }

  void _verify(AppState s) {
    if (s.view == Screen.editor) s.verify();
  }

  void _upload(AppState s) {
    if (s.view == Screen.editor) s.upload();
  }

  void _cog(AppState s) {
    if (s.view == Screen.editor && s.cur != null) s.cog.toggle();
  }

  void _console(AppState s) {
    if (s.view == Screen.editor && s.cur != null) s.togglePanel();
  }

  /// While a project is open the editor stays built (offstage on other screens), so Blockly and Monaco
  /// keep their work, undo history and zoom instead of reloading when you come back.
  Widget _pages(AppState s, bool phone) {
    final open = s.cur != null;
    final onEditor = open && s.view == Screen.editor;
    return Stack(fit: StackFit.expand, children: [
      if (open)
        Offstage(
          key: const ValueKey('editor'),
          offstage: !onEditor,
          child: TickerMode(enabled: onEditor, child: const EditorPage()),
        ),
      if (!onEditor) _view(s, phone),
    ]);
  }

  Widget _view(AppState s, bool phone) {
    switch (s.view) {
      case Screen.projects:
        return const ProjectsPage();
      case Screen.examples:
        return const ExamplesPage();
      case Screen.libraries:
        return const LibrariesPage();
      case Screen.board:
        return const BoardPage();
      case Screen.serial:
        return const SerialPage();
      case Screen.settings:
        return const SettingsPage();
      case Screen.editor:
        return s.cur == null ? const HomePage() : const EditorPage();
      case Screen.home:
        return const HomePage();
    }
  }
}

/// Bottom right, as in the design. An error has an alert icon and a close button, and stays (G-16).
class _Toast extends StatelessWidget {
  const _Toast({required this.text, required this.error});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: EdgeInsets.fromLTRB(14, error ? 6 : 10, error ? 6 : 14, error ? 6 : 10),
        decoration: BoxDecoration(color: kNavy, borderRadius: BorderRadius.circular(8), boxShadow: popShadow),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (error) ...[const RcIcon('alert', size: 16, color: kBrand), const SizedBox(width: 10)],
          Flexible(child: Text(text, style: const TextStyle(fontFamily: fBody, fontSize: 13, height: 18 / 13, color: kCream))),
          if (error) ...[const SizedBox(width: 6), IconBtn('x', onTap: s.closeToast, tip: 'Close', color: kCream, size: 28, iconSize: 16)],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- top bar
const _gearSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="#000">'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(0 12 12)"/>'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(45 12 12)"/>'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(90 12 12)"/>'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(135 12 12)"/>'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(180 12 12)"/>'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(225 12 12)"/>'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(270 12 12)"/>'
    '<rect x="10.3" y="1.2" width="3.4" height="5" rx=".7" transform="rotate(315 12 12)"/>'
    '</g><circle cx="12" cy="12" r="6.2" fill="none" stroke="#000" stroke-width="3.2"/></svg>';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.phone, required this.onMenu});
  final bool phone;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final p = s.view == Screen.editor ? s.cur : null;
    final narrow = MediaQuery.sizeOf(context).width < 1100;
    return Container(
      height: 56,
      padding: EdgeInsets.only(left: phone ? 8 : 20, right: phone ? 8 : 16),
      color: c.top,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (phone) ...[IconBtn('menu', onTap: onMenu, tip: 'Open menu', color: kNavy, iconSize: 20), const SizedBox(width: 4)],
            if (!(phone && p != null))
              Hover(
                onTap: () => s.go(Screen.home),
                tooltip: 'RoboCore IDE home',
                builder: (context, h) => ProductLockup(scale: phone ? .76 : 1, product: !phone),
              ),
            if (!phone) ...[const SizedBox(width: 12), Container(width: 1, height: 24, color: kNavy.withValues(alpha: .2)), const SizedBox(width: 12)],
            // The project name takes the free space itself: a Flexible next to a Spacer would split it in half and leave
            // the right-hand buttons stranded mid-bar on wide windows.
            if (p != null)
              Expanded(
                child: Row(children: [
                  Flexible(child: _ProjectName(p: p)),
                  if (!phone) ...[const SizedBox(width: 12), _SavePill(p: p)],
                ]),
              )
            else if (!phone) ...[
              const SizedBox(width: 260, child: SearchBox()),
              const Spacer(),
            ] else
              const Spacer(),
            const SizedBox(width: 12),
            BoardChip(compact: phone || (narrow && p != null)),
            const SizedBox(width: 12),
            if (p != null) ...[
              CogButton(compact: phone || narrow),
              const SizedBox(width: 8),
              phone
                  ? IconBtn('check', onTap: s.busy == null ? s.verify : null, tip: 'Verify', color: kNavy)
                  : Btn(s.busy == 'verify' ? 'Verifying…' : 'Verify',
                      icon: 'check',
                      kind: BtnKind.ghostTop,
                      busy: s.busy == 'verify',
                      tooltip: 'Verify ($kMod+R)',
                      onTap: s.busy == null ? s.verify : null),
              const SizedBox(width: 8),
              phone
                  ? _PrimaryIcon(icon: 'arrow', onTap: s.busy == null ? s.upload : null, tip: 'Upload')
                  : _TopPrimary(
                      label: s.busy != 'upload' ? 'Upload' : (s.uploadPct == null ? 'Uploading…' : 'Uploading ${s.uploadPct} %'),
                      icon: 'arrow',
                      busy: s.busy == 'upload',
                      progress: s.busy == 'upload' && s.uploadPct != null ? s.uploadPct! / 100 : null,
                      tooltip: 'Upload ($kMod+U)',
                      onTap: s.busy == null ? s.upload : null),
              // Stop: only while a Verify or Upload runs, or the preview board runs the sketch (E-07).
              ListenableBuilder(
                listenable: s.sim,
                builder: (context, _) => !s.canStop
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _PrimaryIcon(
                          icon: 'stop',
                          onTap: s.stop,
                          tip: s.busy == 'upload'
                              ? 'Cancel the upload'
                              : s.busy == 'verify'
                                  ? 'Cancel Verify'
                                  : 'Stop the sketch',
                        ),
                      ),
              ),
            ] else
              phone
                  ? _PrimaryIcon(icon: 'plus', onTap: () => showNewProjectDialog(context), tip: 'New project')
                  : _TopPrimary(label: 'New project', icon: 'plus', onTap: () => showNewProjectDialog(context)),
            if (!phone) ...[
              const SizedBox(width: 12),
              Hover(
                onTap: () => s.go(Screen.settings),
                tooltip: 'Settings',
                builder: (context, h) => Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: h ? Colors.white.withValues(alpha: .3) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                  child: SvgPicture.string(_gearSvg,
                      width: 17, height: 17, colorFilter: const ColorFilter.mode(kNavy, BlendMode.srcIn)),
                ),
              ),
              const SizedBox(width: 8),
              const AccountButton(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Navy button on the yellow bar (stays navy in both themes).
class _TopPrimary extends StatelessWidget {
  const _TopPrimary({required this.label, required this.icon, this.onTap, this.tooltip, this.busy = false, this.progress});
  final String label, icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Uploading: a turning loader, not dimmed, and (with [progress], 0-1) the yellow bar along the bottom.
  final bool busy;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Hover(
      onTap: onTap,
      tooltip: tooltip,
      builder: (context, h) => Opacity(
        opacity: onTap == null && !busy ? .4 : 1,
        child: Container(
          height: 32,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: h && !busy ? kNavyHover : kNavy, borderRadius: BorderRadius.circular(6)),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 14),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (busy) const Spinner(size: 16, color: kCream) else RcIcon(icon, size: 16, color: kCream),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(fontFamily: fBody, fontSize: 13, height: 32 / 13, fontWeight: FontWeight.w600, color: kCream)),
              ]),
            ),
            if (progress != null)
              Positioned(
                left: 0,
                bottom: 0,
                right: 0,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress!.clamp(0.0, 1.0),
                  child: Container(height: 3, color: kBrand),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _PrimaryIcon extends StatelessWidget {
  const _PrimaryIcon({required this.icon, this.onTap, required this.tip});
  final String icon, tip;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        tooltip: tip,
        builder: (context, h) => Container(
          width: 34,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h ? kNavyHover : kNavy, borderRadius: BorderRadius.circular(6)),
          child: RcIcon(icon, size: 16, color: kCream),
        ),
      );
}

/// The project's name in the editor's top bar; opens the project menu (E-02).
class _ProjectName extends StatelessWidget {
  const _ProjectName({required this.p});
  final Project p;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    return MenuButton(
      alignRight: false,
      width: 220,
      entries: () => [
        MenuEntry('Rename…', icon: 'pencil', onTap: () => showRenameProjectDialog(context, p)),
        MenuEntry('Project settings…', icon: 'sliders', onTap: () => showProjectSettingsDialog(context)),
        MenuEntry('Duplicate', icon: 'copy', onTap: () => s.duplicateProject(p)),
        MenuEntry('Download ${p.files.length == 1 ? p.files.first.name : '.zip'}', icon: 'download', onTap: () => s.downloadProject(p)),
        MenuEntry.line,
        MenuEntry('Delete project…', icon: 'trash', onTap: () => showDeleteProjectDialog(context, p)),
      ],
      builder: (context, open, toggle) => _name(open, toggle),
    );
  }

  Widget _name(bool open, VoidCallback toggle) {
    return Hover(
      onTap: toggle,
      tooltip: 'Project menu',
      builder: (context, h) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
            color: h || open ? Colors.white.withValues(alpha: .3) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(p.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: fBody, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: kNavy)),
          ),
          const SizedBox(width: 6),
          const RcIcon('chev', size: 16, color: kNavy),
        ]),
      ),
    );
  }
}

class _SavePill extends StatelessWidget {
  const _SavePill({required this.p});
  final Project p;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final (k, l) = s.saveLabel(p);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (k == 'dirty') ...[const Dot(color: kNavy, size: 7), const SizedBox(width: 6)],
      Text(l,
          style: TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w500, color: kNavy.withValues(alpha: .7))),
    ]);
  }
}

class BoardChip extends StatefulWidget {
  const BoardChip({super.key, this.compact = false});
  final bool compact;
  @override
  State<BoardChip> createState() => _BoardChipState();
}

class _BoardChipState extends State<BoardChip> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final b = kBoards[s.boardId]!;
    final portShort = s.portShort;
    return Popover(
      open: open,
      escCloses: true,
      onClose: () => setState(() => open = false),
      popup: (context) => BoardMenu(onDone: () => setState(() => open = false)),
      child: Hover(
        onTap: () => setState(() => open = !open),
        tooltip: 'Choose board',
        builder: (context, h) => Container(
          height: 40,
          padding: const EdgeInsets.only(left: 8, right: 10),
          decoration: BoxDecoration(
            color: h ? Colors.white : const Color(0xFFFFFCF5),
            border: Border.all(color: const Color(0xFFDBDBD8)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const RcIcon('chip', size: 18, color: kNavy),
            if (!widget.compact) ...[
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, style: const TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: kNavy)),
                  Text('${b.chip} · $portShort',
                      style: const TextStyle(fontFamily: fBody, fontSize: 12, height: 16 / 12, color: Color(0xFF6A7380))),
                ],
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 20, color: const Color(0xFFE7E5E0)),
            ],
            const SizedBox(width: 10),
            Dot(color: kNavy, ring: !s.linked),
            if (!widget.compact) ...[
              const SizedBox(width: 6),
              Text(s.linked ? (s.onUsb ? 'Connected' : 'Preview') : 'Not connected',
                  style: const TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w500, color: kNavy)),
            ],
            const SizedBox(width: 10),
            const RcIcon('chev', size: 16, color: kNavy),
          ]),
        ),
      ),
    );
  }
}

class BoardMenu extends StatelessWidget {
  const BoardMenu({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final cur = s.boardId;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: c.raised,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
        boxShadow: popShadow,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        for (final id in kBoardOrder)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
            child: Hover(
              onTap: () {
                s.pickBoard(id);
                onDone();
              },
              builder: (context, h) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: id == cur ? c.brandSoft : (h ? c.sunk : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  RcIcon('chip', size: 18, color: c.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(kBoards[id]!.name, style: tLabel(c)),
                      Text(kBoards[id]!.spec, style: tCaption(c)),
                    ]),
                  ),
                  if (id == cur) RcIcon('check', size: 16, color: c.ink),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Port', style: tLabel(c, w: FontWeight.w500)),
              const Spacer(),
              ConnStatus(connected: s.linked),
            ]),
            const SizedBox(height: 6),
            RcSelect<String>(
              value: s.port,
              width: 314,
              label: 'Port',
              items: s.portItems,
              onChanged: (v) {
                s.setPort(v);
                onDone();
              },
            ),
            if (s.onUsb && !s.usbOpen) ...[
              const SizedBox(height: 8),
              Btn('Connect USB-C board', icon: 'chip', kind: BtnKind.primary, small: true, onTap: () {
                s.connectUsb();
                onDone();
              }),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: LinkText('Board setup →', onTap: () {
                onDone();
                s.go(Screen.board);
              }),
            ),
          ]),
        ),
      ]),
    );
  }
}

class ConnStatus extends StatelessWidget {
  const ConnStatus({super.key, required this.connected});
  final bool connected;
  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      LinkDot(on: connected),
      const SizedBox(width: 6),
      Text(connected ? 'Connected' : 'Not connected', style: tLabel(c, w: FontWeight.w500)),
    ]);
  }
}

// ---------------------------------------------------------------- search
// Help topics in search (G-11): a page or dialog, found by its name or by a word people might type.
class HelpTopic {
  const HelpTopic(this.name, this.icon, this.words, this.open);
  final String name, icon, words;
  final void Function(BuildContext context, AppState s) open;

  /// Every word typed starts one of the topic's words (so “board” is not found in “keyboard”).
  bool matches(String query) {
    final mine = '$name $words'.toLowerCase().split(RegExp('[^a-z0-9]+'));
    final typed = query.toLowerCase().split(RegExp('[^a-z0-9]+')).where((q) => q.isNotEmpty).toList();
    return typed.isNotEmpty && typed.every((q) => mine.any((w) => w.startsWith(q)));
  }
}

final kHelpTopics = <HelpTopic>[
  HelpTopic('Board Setup', 'chip', 'board usb cable port driver connect upload flash esp32 test connection setup', (_, s) => s.go(Screen.board)),
  HelpTopic('Serial Monitor', 'term', 'serial print println baud monitor output plotter messages', (_, s) => s.go(Screen.serial)),
  HelpTopic('Libraries', 'libs', 'library libraries install include header', (_, s) => s.go(Screen.libraries)),
  HelpTopic('Examples', 'light', 'examples learn start tutorial sample', (_, s) => s.go(Screen.examples)),
  HelpTopic('Settings', 'gear', 'settings preferences theme dark light font size cog level autosave', (_, s) => s.go(Screen.settings)),
  HelpTopic('New project', 'plus', 'new project create start blank', (context, _) => showNewProjectDialog(context)),
  HelpTopic('Keyboard shortcuts', 'keyboard', 'keyboard shortcuts keys hotkeys', (context, _) => showShortcutsDialog(context)),
  HelpTopic('About RoboCore IDE', 'info', 'about version licence license credits', (context, _) => showAboutRoboCoreDialog(context)),
];

class SearchBox extends StatefulWidget {
  const SearchBox({super.key});
  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  String q = '';

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clear() {
    _ctl.clear();
    setState(() => q = '');
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final t = q.trim().toLowerCase();
    final ps = t.isEmpty ? <Project>[] : s.projects.where((p) => p.name.toLowerCase().contains(t)).take(5).toList();
    final es = t.isEmpty ? <Example>[] : kExamples.where((x) => '${x.name} ${x.desc}'.toLowerCase().contains(t)).take(5).toList();
    final hs = t.isEmpty ? <HelpTopic>[] : kHelpTopics.where((h) => h.matches(t)).take(3).toList();
    return Popover(
      open: t.isNotEmpty,
      alignRight: false,
      onClose: _clear,
      popup: (context) => Container(
        width: 320,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: c.raised, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(10), boxShadow: popShadow),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (ps.isNotEmpty) _h(c, 'Projects'),
          for (final p in ps)
            _row(c, p.hasBlocks && p.mode == 'blocks' ? 'blocks' : 'code', p.name, kBoards[p.board]!.name, () {
              _clear();
              s.openProject(p.id);
            }),
          if (es.isNotEmpty) _h(c, 'Examples'),
          for (final e in es)
            _row(c, kExIcon[e.id] ?? 'bolt', e.name, e.cat, () {
              _clear();
              s.openExample(e.id);
            }),
          if (hs.isNotEmpty) _h(c, 'Help'),
          for (final h in hs)
            _row(c, h.icon, h.name, 'Help', () {
              _clear();
              h.open(context, s);
            }),
          if (ps.isEmpty && es.isEmpty && hs.isEmpty)
            Padding(padding: const EdgeInsets.all(12), child: Text('Nothing matches “$q”.', style: tCaption(c))),
        ]),
      ),
      // Esc clears the search and closes the results (G-11); the field keeps its own focus.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && (q.isNotEmpty || _focus.hasFocus)) {
            _clear();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: RcInput(
          controller: _ctl,
          focusNode: _focus,
          hint: 'Search',
          icon: 'search',
          onChanged: (v) => setState(() => q = v),
          onSubmitted: (_) {
            if (ps.isNotEmpty) {
              final id = ps.first.id;
              _clear();
              s.openProject(id);
            } else if (es.isNotEmpty) {
              final id = es.first.id;
              _clear();
              s.openExample(id);
            } else if (hs.isNotEmpty) {
              final h = hs.first;
              _clear();
              h.open(context, s);
            }
          },
        ),
      ),
    );
  }

  Widget _h(RC c, String t) =>
      Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 4), child: Text(t.toUpperCase(), style: tOverline(c, color: c.faint)));

  Widget _row(RC c, String icon, String name, String sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Hover(
          onTap: onTap,
          builder: (context, h) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(color: h ? c.sunk : Colors.transparent, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              RcIcon(icon, size: 16, color: c.ink),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: tLabel(c), overflow: TextOverflow.ellipsis)),
              Text(sub, style: tCaption(c, color: c.faint)),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------- sidebar
const _nav = [
  (Screen.home, 'Home', 'home'),
  (Screen.projects, 'Projects', 'folder'),
  (Screen.libraries, 'Libraries', 'libs'),
  (Screen.examples, 'Examples', 'light'),
  null,
  (Screen.board, 'Board Setup', 'chip'),
  (Screen.serial, 'Serial Monitor', 'term'),
];

class SideBar extends StatelessWidget {
  const SideBar({super.key, required this.collapsed, this.onNavigate});
  final bool collapsed;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final rp = s.cur ?? (s.sortedProjects.isEmpty ? null : s.sortedProjects.first);
    void nav(Screen v) {
      onNavigate?.call();
      s.go(v);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: collapsed ? 64 : 208,
      padding: EdgeInsets.fromLTRB(collapsed ? 10 : 12, 12, collapsed ? 10 : 12, 10),
      decoration: BoxDecoration(color: c.bg, border: Border(right: BorderSide(color: c.line2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (rp != null)
          Hover(
            onTap: () {
              onNavigate?.call();
              s.openProject(rp.id);
            },
            tooltip: collapsed ? 'Open ${rp.name}' : null,
            builder: (context, h) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10, vertical: 8),
              decoration: BoxDecoration(
                color: s.view == Screen.editor ? c.surface : (h ? c.sunk : Colors.transparent),
                border: Border.all(color: s.view == Screen.editor ? c.ink : c.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                RcIcon(rp.mode == 'blocks' ? 'blocks' : 'code', size: 18, color: c.ink),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('OPEN PROJECT', style: tOverline(c, color: c.faint)),
                      Text(rp.name, style: tLabel(c), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  RcIcon('chevr', size: 16, color: c.ink),
                ],
              ]),
            ),
          ),
        for (final n in _nav)
          if (n == null)
            const SizedBox(height: 10)
          else
            _NavItem(
              icon: n.$3,
              label: n.$2,
              on: s.view == n.$1,
              collapsed: collapsed,
              dot: n.$1 == Screen.serial && (s.onUsb ? s.usbOpen : s.sim.running),
              onTap: () => nav(n.$1),
            ),
        const Spacer(),
        _NavItem(icon: 'gear', label: 'Settings', on: s.view == Screen.settings, collapsed: collapsed, onTap: () => nav(Screen.settings)),
        const SizedBox(height: 2),
        Container(
          padding: EdgeInsets.only(top: 10, left: collapsed ? 0 : 12, right: collapsed ? 0 : 4),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line2))),
          child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween, children: [
            if (!collapsed)
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('BUILD. CODE. CREATE.', style: tOverline(c), maxLines: 1),
                ),
              ),
            if (onNavigate == null)
              IconBtn('panel', onTap: s.toggleSidebar, tip: collapsed ? 'Expand sidebar' : 'Collapse sidebar'),
          ]),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.on, required this.collapsed, required this.onTap, this.dot = false});
  final String icon, label;
  final bool on, collapsed, dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Hover(
        onTap: onTap,
        tooltip: collapsed ? label : null,
        builder: (context, h) => Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
          decoration: BoxDecoration(
            color: on ? c.brandSoft : (h ? c.ink.withValues(alpha: .05) : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            if (on)
              Positioned(
                left: collapsed ? 0 : -12,
                top: 10,
                child: Container(
                  width: 3,
                  height: 18,
                  decoration: const BoxDecoration(color: kBrand, borderRadius: BorderRadius.horizontal(right: Radius.circular(2))),
                ),
              ),
            Positioned.fill(
              child: Row(mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                RcIcon(icon, size: 20, color: c.ink),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: tLabel(c, color: on ? c.ink : c.muted, w: on ? FontWeight.w600 : FontWeight.w500)),
                  ),
                  if (dot) Dot(color: c.ok, size: 6),
                ],
              ]),
            ),
            if (collapsed && dot) Positioned(right: 6, top: 8, child: Dot(color: c.ok, size: 6)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- status bar
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.phone});
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final b = kBoards[s.boardId]!;
    final p = s.cur;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line2))),
      child: Row(children: [
        // Ink dot, the box yellow while busy, a warning icon on an error (the design's Connection Status).
        if (s.stateKind == 'err')
          RcIcon('alert', size: 13, color: c.ink)
        else
          Dot(size: 7, color: s.stateKind == 'busy' ? kBrand : c.ink),
        const SizedBox(width: 6),
        Text(s.stateLabel, style: tCaption(c, color: c.ink, w: FontWeight.w500)),
        const SizedBox(width: 16),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: s.logTick,
            builder: (context, _, __) => Text(_detail(s, p), style: tCaption(c, color: c.faint), overflow: TextOverflow.ellipsis),
          ),
        ),
        if (!phone)
          Hover(
            onTap: () => s.go(Screen.board),
            tooltip: 'Board setup',
            builder: (context, h) => Text('${b.name} · ${s.linked ? s.portLabel : 'not connected'} · ${s.baud} baud',
                style: tCaption(c, color: h ? c.ink : c.faint).copyWith(decoration: h ? TextDecoration.underline : null)),
          ),
        if (s.view == Screen.editor && p != null && p.mode == 'code') ...[
          const SizedBox(width: 16),
          Text(s.cursorPos, style: tCaption(c, color: c.faint)),
        ],
      ]),
    );
  }

  String _detail(AppState s, Project? p) {
    switch (s.view) {
      case Screen.home:
        final n = s.projects.length;
        return '$n project${n == 1 ? '' : 's'} · saved on this device';
      case Screen.projects:
        final n = s.projects.length;
        if (n == 0) return 'No projects yet';
        return '${s.filteredProjects.length} of $n project${n == 1 ? '' : 's'} · saved on this device';
      case Screen.examples:
        return '${kExamples.length} examples';
      case Screen.libraries:
        final inc = kLibs.where((l) => l.kind == 'included').length;
        final ins = kLibs.where((l) => l.kind == 'opt' && (s.libs[l.id] ?? false)).length;
        return '$inc included · $ins installed';
      case Screen.board:
        return 'RoboCore library 1.0 · esp32 core 3.3.12 · schematic rev 2.0';
      case Screen.serial:
        return '${s.log.length} lines received';
      case Screen.settings:
        return 'Saved on this device';
      case Screen.editor:
        if (p == null) return '';
        final v = s.verified;
        if (v != null) return '${fmtN(v.size)} bytes (${v.pct}%) · RAM ${v.rp}%';
        final t = clock(DateTime.fromMillisecondsSinceEpoch(p.updated));
        if (p.mode == 'blocks') {
          final n = p.blocklyCount ?? p.setup.length + p.loop.length;
          return '$n block${n == 1 ? '' : 's'} · saved $t';
        }
        return '${p.files[s.file.clamp(0, p.files.length - 1).toInt()].name} · C++ · saved $t';
    }
  }
}
