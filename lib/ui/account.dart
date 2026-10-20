// The account button in the top bar (G-10): who is using this device, Edit profile, Keyboard shortcuts and About.
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import '../state/app_state.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'dialogs.dart' show DialogFrame;
import 'widgets/brand.dart';
import 'widgets/common.dart';
import 'widgets/popover.dart';

/// Keep in step with `version:` in pubspec.yaml.
const kAppVersion = '1.0.0';

class AccountButton extends StatefulWidget {
  const AccountButton({super.key});
  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
  bool open = false;

  void _close() => setState(() => open = false);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Popover(
      open: open,
      onClose: _close,
      popup: (_) => AccountMenu(onDone: _close),
      child: Hover(
        onTap: () => setState(() => open = !open),
        tooltip: 'Account',
        builder: (context, h) => Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h || open ? kNavyHover : kNavy, shape: BoxShape.circle),
          child: Text(s.initials,
              style: const TextStyle(
                  fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: kBrand)),
        ),
      ),
    );
  }
}

class AccountMenu extends StatefulWidget {
  const AccountMenu({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<AccountMenu> {
  // Asked for outright: autofocus would do nothing while an editor still holds the focus.
  final _focus = FocusNode(debugLabel: 'Account menu');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onDone = widget.onDone;
    final s = AppScope.of(context);
    final c = RC.of(context);
    Widget item(String icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Hover(
            onTap: () {
              onDone();
              onTap();
            },
            builder: (context, h) => Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: h ? c.sunk : Colors.transparent, borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                RcIcon(icon, size: 16, color: c.ink),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: tLabel(c, w: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        );
    // Esc closes the menu (G-15).
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          onDone();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: c.raised,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(10),
          boxShadow: popShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.user, style: tLabel(c), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(s.school.isEmpty ? 'This device' : '${s.school} · this device',
                  style: tCaption(c, color: c.faint), overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(height: 4),
          item('user', 'Edit profile', () => s.go(Screen.settings)),
          item('keyboard', 'Keyboard shortcuts', () => showShortcutsDialog(context)),
          item('info', 'About RoboCore IDE', () => showAboutRoboCoreDialog(context)),
          const SizedBox(height: 4),
        ]),
      ),
    );
  }
}

bool get _mac => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

Future<void> showShortcutsDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (_) => const _ShortcutsDialog(),
    );

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final m = _mac ? '⌘' : 'Ctrl';
    // Only the shortcuts the IDE really has: the top-bar ones (shell.dart) and those of Monaco and Blockly.
    final groups = <(String, List<(String, String)>)>[
      ('In the IDE', [('Save', '$m+S'), ('Verify', '$m+R'), ('Upload', '$m+U'), ('Ask Cog', '$m+I')]),
      (
        'In the code editor',
        [
          ('Find', '$m+F'),
          ('Suggestions', 'Ctrl+Space'),
          ('Quick fix, Explain with Cog', '$m+.'),
          ('Undo / redo', '$m+Z / $m+Shift+Z'),
        ]
      ),
      (
        'In the blocks',
        [
          ('Zoom in / out / reset', '$m+= / $m+− / $m+0'),
          ('Undo / redo', '$m+Z / $m+Shift+Z'),
          ('Copy / paste a block', '$m+C / $m+V'),
          ('Delete a block', 'Delete'),
        ]
      ),
      ('Menus and dialogs', [('Close', 'Esc')]),
    ];
    return DialogFrame(
      title: 'Keyboard shortcuts',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (title, rows) in groups) ...[
          if (title != groups.first.$1) const SizedBox(height: 14),
          Text(title.toUpperCase(), style: tOverline(c)),
          const SizedBox(height: 4),
          for (final (action, keys) in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
              child: Row(children: [
                Expanded(child: Text(action, style: tBody(c, size: 13, height: 18 / 13))),
                const SizedBox(width: 12),
                Text(keys, style: tMono(c, size: 12, color: c.muted, height: 18 / 12)),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          'While you’re typing in the code or blocks area, keys go to that editor: click outside it first for Save, '
          'Verify, Upload and Ask Cog, or use the buttons in the top bar.',
          style: tCaption(c, color: c.faint),
        ),
      ]),
      actions: [Btn('Done', kind: BtnKind.primary, onTap: () => Navigator.of(context).pop())],
    );
  }
}

Future<void> showAboutRoboCoreDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (_) => const _AboutDialog(),
    );

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    const lines = [
      'Blocks editor: Google Blockly (Apache 2.0)',
      'Code editor: Monaco (MIT)',
      'Uploads: esptool-js (Apache 2.0) over Web Serial',
      'Compiling: arduino-cli and the esp32 core, on the compile server',
      'Ask Cog: Claude by Anthropic, through the compile server',
    ];
    return DialogFrame(
      title: 'About RoboCore IDE',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const AppIconTile(size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RoboCore IDE', style: tLabel(c).copyWith(fontSize: 15, height: 20 / 15)),
              const SizedBox(height: 2),
              Text('Version $kAppVersion', style: tCaption(c)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(l, style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
          ),
        const SizedBox(height: 6),
        Text('Designed in Zambia by Plastal-Bot Builders.', style: tBody(c, size: 13, height: 18 / 13)),
      ]),
      actions: [Btn('Done', kind: BtnKind.primary, onTap: () => Navigator.of(context).pop())],
    );
  }
}
