// The account button in the top bar (G-10): who is using this device, Edit profile, Keyboard shortcuts and About.
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'dialogs.dart' show DialogFrame;
import 'widgets/brand.dart';
import 'widgets/common.dart';
import 'widgets/menu.dart';

/// Keep in step with `version:` in pubspec.yaml.
const kAppVersion = '1.0.0';

class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    return MenuButton(
      width: 260,
      header: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.user.isEmpty ? 'No name set' : s.user, style: tLabel(c), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(s.school.isEmpty ? 'This device' : '${s.school} · this device', style: tCaption(c, color: c.faint), overflow: TextOverflow.ellipsis),
        ]),
      ),
      entries: () => [
        MenuEntry('Edit profile', icon: 'user', onTap: () => s.go(Screen.settings)),
        MenuEntry('Keyboard shortcuts', icon: 'keyboard', onTap: () => showShortcutsDialog(context)),
        MenuEntry('About RoboCore IDE', icon: 'info', onTap: () => showAboutRoboCoreDialog(context)),
      ],
      builder: (context, open, toggle) => Hover(
        onTap: toggle,
        tooltip: 'Account',
        builder: (context, h) => Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h || open ? kNavyHover : kNavy, shape: BoxShape.circle),
          child: s.initials.isEmpty
              ? const RcIcon('user', size: 16, color: kBrand)
              : Text(s.initials,
                  style: const TextStyle(
                      fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: kBrand)),
        ),
      ),
    );
  }
}

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
    final m = kMod;
    // Only the shortcuts the IDE really has: the top-bar ones (shell.dart) and those of Monaco and Blockly.
    final groups = <(String, List<(String, String)>)>[
      ('In the IDE', [
        ('Save', '$m+S'),
        ('Verify', '$m+R'),
        ('Upload', '$m+U'),
        ('Ask Cog', '$m+I'),
        ('Collapse the sidebar', '$m+B'),
        ('Show or hide the console', '$m+J'),
      ]),
      (
        'In the code editor',
        [
          ('Find', '$m+F'),
          ('Suggestions', 'Ctrl+Space'),
          ('Quick fix, Explain with Cog', '$m+.'),
          ('Undo / redo', '$m+Z / $m+Shift+Z'),
          // Monaco's Toggle Tab Key Moves Focus; until then Tab types a tab in the code.
          ('Let Tab leave the editor (or type tabs again)', m == 'Cmd' ? 'Ctrl+Shift+M' : 'Ctrl+M'),
        ]
      ),
      (
        'In the blocks',
        [
          ('Zoom in / out / reset', '$m+= / $m+− / $m+0'),
          ('Undo / redo', '$m+Z / $m+Shift+Z'),
          ('Copy / paste a block', '$m+C / $m+V'),
          ('Delete a block', 'Delete'),
          ('Move between blocks', 'Arrow keys'),
          ('Edit the field', 'Enter'),
          ('Open the toolbox', 'T'),
        ]
      ),
      (
        'Moving around',
        [
          ('Next / previous button or field', 'Tab / Shift+Tab'),
          ('Press the button', 'Enter or Space'),
          ('Move in a menu', 'Arrow keys'),
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
          'These work anywhere in the IDE, also while you’re typing in the code or blocks.',
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
