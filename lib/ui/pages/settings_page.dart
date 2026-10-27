import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/cog.dart';
import '../../state/models.dart' show Settings;
import '../../theme.dart';
import '../app_scope.dart';
import '../cog/cog_panel.dart' show CogMark;
import '../dialogs.dart' show DialogFrame, RadioDot;
import '../widgets/common.dart';
import '../widgets/ui_scale.dart';
import 'home_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final st = s.settings;

    Widget card(String title, List<Widget> rows) => RcCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title.toUpperCase(), style: tH2(c))),
            for (var i = 0; i < rows.length; i++)
              Container(
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line2))),
                child: rows[i],
              ),
          ]),
        );

    Widget row(String label, Widget trailing, {String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: tLabel(c, w: FontWeight.w500)),
                if (hint != null) ...[const SizedBox(height: 2), Text(hint, style: tCaption(c))],
              ]),
            ),
            const SizedBox(width: 16),
            trailing,
          ]),
        );

    // The design's Theme Choice: name and description, the radio on the right.
    Widget theme(String key, String name, String desc) {
      final on = st.theme == key;
      return Hover(
        onTap: () => s.updateSettings((x) => x.theme = key),
        builder: (context, h) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: on ? c.brandSoft : (h ? c.sunk : Colors.transparent),
            border: Border.all(color: on ? c.ink : c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: tLabel(c)),
                Text(desc, style: tCaption(c), overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 10),
            RadioDot(on: on),
          ]),
        ),
      );
    }

    final phone = MediaQuery.sizeOf(context).width < 760;
    final themes = [
      theme('paper', 'Paper', 'Light · the box colours'),
      theme('navy', 'Navy', 'Dark · the box, inverted'),
    ];

    final profile = card('Profile', [const _ProfileRow()]);
    final appearance = card('Appearance', [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: phone
            ? Column(children: [themes[0], const SizedBox(height: 12), themes[1]])
            : Row(children: [Expanded(child: themes[0]), const SizedBox(width: 12), Expanded(child: themes[1])]),
      ),
      // The web app has the browser's own zoom (⌘ + and ⌘ −) on top of this.
      row(
          'Display size',
          RcSelect<double>(
            value: st.uiScale,
            width: 150,
            label: 'Display size',
            items: [
              (0.0, 'Auto (${(autoUiScale(context) * 100).round()} %)'),
              for (final v in kUiScales) (v, '${(v * 100).round()} %'),
            ],
            onChanged: (v) => s.updateSettings((x) => x.uiScale = v),
          ),
          hint: 'How big everything is. Auto fits the screen: bigger on a large display.'),
    ]);
    final editor = card('Editor', [
      row(
          'Font size',
          RcSelect<int>(
            value: st.fontSize,
            width: 110,
            label: 'Font size',
            // The design's sizes; a size saved before (15 or 18 px) stays in the list.
            items: [for (final n in ({12, 13, 14, 16, st.fontSize}.toList()..sort())) (n, '$n px')],
            onChanged: (v) => s.updateSettings((x) => x.fontSize = v),
          )),
      row('Autocomplete', RcSwitch(value: st.autocomplete, label: 'Autocomplete', onChanged: (v) => s.updateSettings((x) => x.autocomplete = v)),
          hint: 'Suggest Arduino functions as you type.'),
      row('Word wrap', RcSwitch(value: st.wrap, label: 'Word wrap', onChanged: (v) => s.updateSettings((x) => x.wrap = v))),
    ]);
    final board = card('Real board and upload', [const _CompileServerRow()]);
    // With a teacher PIN, turning Cog on or off and what it may read ask for it too.
    Future<void> locked(void Function(Settings x) change) async {
      if (await _unlock(context, s)) s.updateSettings(change);
    }

    final cog = card('Cog — learning partner', [
      row(
          'Cog',
          RcSwitch(
              value: st.cogOn,
              label: 'Cog',
              onChanged: (v) => locked((x) {
                    x.cogOn = v;
                    if (!v) s.cog.close();
                  })),
          hint: 'An AI helper (Claude, made by Anthropic) that answers through the RoboCore server.'),
      const _CogStyleRow(),
      row(
          'Explanation level',
          RcSelect<String>(
            value: st.cogLevel,
            width: 150,
            label: 'Explanation level',
            items: const [('beginner', 'Beginner'), ('intermediate', 'Intermediate'), ('advanced', 'Advanced')],
            onChanged: (v) => s.updateSettings((x) => x.cogLevel = v),
          ),
          hint: 'How much Cog assumes you already know.'),
      row('Let Cog read this project', RcSwitch(value: st.cogRead, label: 'Let Cog read this project', onChanged: (v) => locked((x) => x.cogRead = v)),
          hint: 'Sends the project’s files and problems, and the last lines of Output and the Serial Monitor, with each '
              'question. When off, Cog gets only what you type.'),
      const _CogStatusRow(),
    ]);
    // The Mac app: where the projects are kept (Settings → Projects folder).
    final f = s.folder;
    final projectsFolder = s.chooseFolder == null
        ? null
        : card('Projects folder', [
            row(
              f != null ? 'Projects are files' : 'Projects are kept in the app',
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (f != null) ...[Btn('Show in Finder', icon: 'open', onTap: () => f.reveal()), const SizedBox(width: 8)],
                Btn(f != null ? 'Change…' : 'Choose folder…', icon: 'folder', onTap: () => s.chooseProjectsFolder()),
              ]),
              hint: f != null
                  ? '${f.path}: one sketch folder for each project, which the Arduino IDE can open too.'
                  : s.missingFolder != null
                      ? '${s.missingFolder} can’t be opened. Choose it again, or another folder.'
                      : 'Choose a folder (Documents is a good place) to keep each project as a folder of .ino files you '
                          'can see in Finder, back up and open in the Arduino IDE.',
            ),
          ]);
    final general = card('General', [
      row('Language', RcSelect<String>(value: st.lang, width: 130, label: 'Language', items: const [('English', 'English')], onChanged: (_) {})),
      row('Auto-save projects', RcSwitch(value: st.autosave, label: 'Auto-save projects', onChanged: (v) => s.updateSettings((x) => x.autosave = v)),
          hint: 'Saves a moment after each change, and before upload.'),
      row('Reset all data', Btn('Reset…', icon: 'trash', onTap: () => _confirmReset(context)),
          hint: 'Deletes this device’s projects, profile and settings.'),
    ]);

    Widget column(List<Widget> cards) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 20), cards[i]],
        ]);

    return PageBody(children: [
      const PageHeader(title: 'Settings', subtitle: 'Saved automatically on this device.'),
      // Two columns on wide windows, as in the design: you and Cog on the left, the app on the right.
      LayoutBuilder(
        builder: (context, k) => k.maxWidth >= 1000
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: column([profile, cog])),
                const SizedBox(width: 20),
                Expanded(child: column([appearance, editor, board, if (projectsFolder != null) projectsFolder, general])),
              ])
            : Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: column([profile, appearance, editor, board, if (projectsFolder != null) projectsFolder, cog, general]),
                ),
              ),
      ),
    ]);
  }

  /// “Reset all data?” (ST-12).
  void _confirmReset(BuildContext context) {
    final s = AppScope.read(context);
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (dctx) {
        void reset() {
          Navigator.of(dctx).pop();
          s.resetAll();
        }

        return DialogFrame(
          title: 'Reset all data?',
          subtitle: s.folder != null
              ? 'Deletes your profile and settings, then starts again at the welcome screen. Your project files stay in '
                  '${s.folder!.path}; RoboCore just stops using that folder.'
              : 'Deletes this device’s projects, profile and settings, then starts again at the welcome screen. You can’t undo it.',
          onSubmit: reset,
          actions: [
            Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(dctx).pop()),
            Btn('Reset', icon: 'trash', kind: BtnKind.primary, onTap: reset),
          ],
        );
      },
    );
  }
}

/// Settings → Compile server: the address of the server that compiles C++ for the real board.
class _CompileServerRow extends StatefulWidget {
  const _CompileServerRow();
  @override
  State<_CompileServerRow> createState() => _CompileServerRowState();
}

class _CompileServerRowState extends State<_CompileServerRow> {
  final _ctl = TextEditingController();
  bool _testing = false;

  /// With a teacher PIN the address can't be edited until the PIN is typed (Cog's data goes there).
  bool _unlocked = false;
  (bool, String)? _result;

  @override
  void initState() {
    super.initState();
    _ctl.text = AppScope.read(context).settings.compileServer;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    if (!mounted) return;
    final s = AppScope.read(context);
    s.setCompileServer(_ctl.text);
    _ctl.text = s.settings.compileServer;
  }

  Future<void> _test() async {
    if (_unlocked || AppScope.read(context).settings.cogPin.isEmpty) _save();
    setState(() {
      _testing = true;
      _result = null;
    });
    final r = await AppScope.read(context).checkServer();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final s = AppScope.of(context);
    final locked = s.settings.cogPin.isNotEmpty && !_unlocked;
    final r = _result;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Compile server', style: tLabel(c, w: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(
          AppScope.of(context).local != null
              ? 'This Mac compiles for its boards itself, with no internet. The compile server is only used for a board '
                  'this Mac can’t build. server/README.md shows how to run one (Docker, Render or Cloud Run).'
              : 'Verify and Upload use it to compile your C++ with arduino-cli and the esp32 core, then the IDE flashes '
                  'the board over USB-C. Without it, Verify uses the built-in preview check and Upload runs the preview board. '
                  'server/README.md shows how to run one (Docker, Render or Cloud Run).',
          style: tCaption(c),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: locked
                ? _LockedField(s.settings.compileServer.isEmpty ? 'Not set' : s.settings.compileServer)
                : Focus(
                    onFocusChange: (has) {
                      if (!has) _save();
                    },
                    child: RcInput(
                      controller: _ctl,
                      hint: 'https://robocore-compile.example.com',
                      height: 36,
                      onSubmitted: (_) => _save(),
                    ),
                  ),
          ),
          if (locked) ...[
            const SizedBox(width: 8),
            Btn('Change…', height: 36, onTap: () async {
              if (await _unlock(context, s)) setState(() => _unlocked = true);
            }),
          ],
          const SizedBox(width: 8),
          Btn(_testing ? 'Testing…' : 'Test', icon: 'plug', busy: _testing, height: 36, onTap: _testing ? null : _test),
        ]),
        if (r != null) ...[
          const SizedBox(height: 8),
          Text(r.$2, style: tCaption(c, color: c.ink, w: r.$1 ? FontWeight.w400 : FontWeight.w600)),
        ],
      ]),
    );
  }
}

/// Settings → Profile: the name (and school or class) the IDE greets this device's user with.
class _ProfileRow extends StatefulWidget {
  const _ProfileRow();
  @override
  State<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends State<_ProfileRow> {
  final _name = TextEditingController();
  final _school = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context);
    _name.text = s.user;
    _school.text = s.school;
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    super.dispose();
  }

  void _save() {
    final s = AppScope.read(context);
    final e = s.validateProfileName(_name.text);
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    s.setProfile(name: _name.text, school: _school.text);
    setState(() => _error = null);
    s.showToast('Profile saved', body: 'Shown on Home and in the account menu.');
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;
    Widget field(String label, TextEditingController ctl, String hint, {bool err = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: tLabel(c, color: c.muted, w: FontWeight.w500)),
            const SizedBox(height: 6),
            RcInput(
              controller: ctl,
              hint: hint,
              height: 36,
              error: err,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
          ],
        );
    final name = field('First name or nickname', _name, 'Optional', err: _error != null);
    final school = field('School or class', _school, 'Optional');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        phone
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [name, const SizedBox(height: 12), school])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: name),
                const SizedBox(width: 12),
                Expanded(child: school),
              ]),
        if (_error != null) ...[const SizedBox(height: 6), Text(_error!, style: tCaption(c, color: c.err, w: FontWeight.w600))],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('Kept on this device only. Each computer or browser has its own profile and projects.', style: tCaption(c))),
          const SizedBox(width: 12),
          Btn('Save', kind: BtnKind.primary, height: 34, onTap: _save),
        ]),
      ]),
    );
  }
}

/// The teacher PIN dialog: the PIN, or ([create]) a new one typed twice. null = cancelled.
Future<String?> _pin(BuildContext context, {required String title, required String body, bool create = false}) {
  final a = TextEditingController(), b = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      final c = RC.of(context);
      String? error;
      return StatefulBuilder(builder: (context, set) {
        void done() {
          final pin = a.text.trim();
          if (pin.length < 4) return set(() => error = 'Use at least 4 digits.');
          if (create && pin != b.text.trim()) return set(() => error = 'The two PINs are different.');
          Navigator.pop(context, pin);
        }

        Widget field(TextEditingController t, String hint, {bool autofocus = false}) => TextField(
              controller: t,
              autofocus: autofocus,
              obscureText: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => done(),
              style: tBody(c, size: 14),
              decoration: InputDecoration(hintText: hint, isDense: true, border: const OutlineInputBorder()),
            );
        return AlertDialog(
          backgroundColor: c.raised,
          title: Text(title.toUpperCase(), style: tH2(c)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(body, style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
              const SizedBox(height: 14),
              field(a, 'Teacher PIN', autofocus: true),
              if (create) ...[const SizedBox(height: 8), field(b, 'The same PIN again')],
              if (error != null) ...[const SizedBox(height: 8), Text(error!, style: tCaption(c, color: c.err, w: FontWeight.w600))],
            ]),
          ),
          actions: [
            Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.pop(context)),
            Btn(create ? 'Set PIN' : 'OK', kind: BtnKind.primary, onTap: done),
          ],
        );
      });
    },
  );
}

/// Asks for the PIN when one is set. true = go ahead.
Future<bool> _unlock(BuildContext context, AppState s) async {
  if (s.settings.cogPin.isEmpty) return true;
  final pin = await _pin(context, title: 'Teacher PIN', body: 'A teacher locked Cog’s settings and the server address. Type the PIN to change them.');
  if (pin == null) return false;
  if (cogPinHash(pin) == s.settings.cogPin) return true;
  s.showToast('That PIN is not right', body: 'Try again, or ask the teacher who set it.', error: true);
  return false;
}

/// Settings → Cog: how much Cog shows. "Write code for me" and, once a teacher PIN is set, any change
/// of style need the PIN.
class _CogStyleRow extends StatelessWidget {
  const _CogStyleRow();

  Future<void> _pick(BuildContext context, AppState s, String style) async {
    if (s.settings.cogStyle == style) return;
    if (style == 'write' && s.settings.cogPin.isEmpty) {
      final pin = await _pin(context,
          create: true,
          title: 'Teacher PIN',
          body: '“Write code for me” is for teachers to turn on. Set a teacher PIN: it will also be needed to change the help style.');
      if (pin == null) return;
      s.updateSettings((x) {
        x.cogPin = cogPinHash(pin);
        x.cogStyle = style;
      });
      return;
    }
    if (!context.mounted || !await _unlock(context, s)) return;
    s.updateSettings((x) => x.cogStyle = style);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final st = s.settings;
    Widget option(String key, String desc, {bool locked = false}) {
      final on = st.cogStyle == key;
      return Hover(
        onTap: () => _pick(context, s, key),
        builder: (context, h) => Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: on ? c.brandSoft : (h ? c.sunk : Colors.transparent),
            border: Border.all(color: on ? c.ink : c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          // The design's Help Style: title and description, the radio on the right.
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kCogStyles[key]!, style: tLabel(c)),
                Text(desc, style: tCaption(c)),
              ]),
            ),
            if (locked && st.cogPin.isEmpty) ...[const SizedBox(width: 8), Badge2('Teacher')],
            const SizedBox(width: 10),
            RadioDot(on: on),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const CogMark(size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text('Cog explains errors and blocks, gives hints one at a time, and checks what you learned.', style: tBody(c, size: 13, height: 18 / 13))),
        ]),
        const SizedBox(height: 14),
        Text('How should Cog help?', style: tLabel(c, color: c.muted, w: FontWeight.w500)),
        const SizedBox(height: 8),
        option('hints', 'Explains, then gives hints one at a time. Shows the fix only after two hints. (Default)'),
        option('explain', 'Explains the problem and the fix in words.'),
        option('write', 'Can write and change code when asked. Off for students.', locked: true),
        Row(children: [
          Expanded(
            child: Text(
              st.cogPin.isEmpty
                  ? 'Teachers can lock Cog’s settings for a class with a PIN.'
                  : 'Locked with a teacher PIN: changing Cog’s settings or the server address asks for it.',
              style: tCaption(c),
            ),
          ),
          if (st.cogPin.isEmpty)
            Btn('Set a teacher PIN', kind: BtnKind.plain, onTap: () async {
              final pin = await _pin(context,
                  create: true,
                  title: 'Teacher PIN',
                  body: 'With a PIN, students can’t turn Cog on or off, change what it reads, its help style, the server '
                      'address or the school key, or turn on “Write code for me”.');
              if (pin != null) s.updateSettings((x) => x.cogPin = cogPinHash(pin));
            })
          else
            Btn('Remove the PIN', kind: BtnKind.plain, onTap: () async {
              if (!await _unlock(context, s)) return;
              s.updateSettings((x) {
                x.cogPin = '';
                if (x.cogStyle == 'write') x.cogStyle = 'hints';
              });
            }),
        ]),
      ]),
    );
  }
}

/// Whether the RoboCore server has Cog, with the offline note when it can't be reached.
class _CogStatusRow extends StatefulWidget {
  const _CogStatusRow();
  @override
  State<_CogStatusRow> createState() => _CogStatusRowState();
}

class _CogStatusRowState extends State<_CogStatusRow> {
  (bool?, String)? _status;
  bool _busy = false;
  final _key = TextEditingController();

  /// With a teacher PIN the key can't be changed until the PIN is typed.
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _key.text = AppScope.read(context).settings.cogKey;
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _saveKey() {
    if (!mounted) return;
    final s = AppScope.read(context);
    final k = _key.text.trim();
    if (k != s.settings.cogKey && (_unlocked || s.settings.cogPin.isEmpty)) s.updateSettings((x) => x.cogKey = k);
  }

  Future<void> _test() async {
    _saveKey();
    final s = AppScope.read(context);
    setState(() => _busy = true);
    final r = await s.cog.client.status(s.settings.compileServer, key: s.settings.cogKey);
    if (mounted) {
      setState(() {
        _status = r;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final s = AppScope.of(context);
    final locked = s.settings.cogPin.isNotEmpty && !_unlocked;
    final st = _status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cog on the RoboCore server', style: tLabel(c, w: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('Cog answers through the server above. Its Anthropic API key stays on the server.', style: tCaption(c)),
            ]),
          ),
          const SizedBox(width: 16),
          Btn(_busy ? 'Testing…' : 'Test Cog', kind: BtnKind.outline, busy: _busy, onTap: _busy ? null : _test),
        ]),
        const SizedBox(height: 12),
        Text('School key', style: tLabel(c, w: FontWeight.w500)),
        const SizedBox(height: 2),
        Text('The server only answers schools with a key, so nobody else can use its Anthropic credit. Ask whoever runs it.',
            style: tCaption(c)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: locked
                ? _LockedField(s.settings.cogKey.isEmpty ? 'Not set' : '••••••••')
                : Focus(
                    onFocusChange: (has) {
                      if (!has) _saveKey();
                    },
                    child: RcInput(controller: _key, hint: 'School key', height: 36, obscure: true, onSubmitted: (_) => _saveKey()),
                  ),
          ),
          if (locked) ...[
            const SizedBox(width: 8),
            Btn('Change…', height: 36, onTap: () async {
              if (await _unlock(context, s)) setState(() => _unlocked = true);
            }),
          ],
        ]),
        if (st != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.sunk, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RcIcon(st.$1 == true ? 'check' : 'alert', size: 18, color: st.$1 == true ? c.ok : c.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(st.$1 == null ? 'Cog is offline' : (st.$1! ? 'Cog is ready' : 'Cog isn’t set up'), style: tLabel(c)),
                  const SizedBox(height: 2),
                  Text(st.$2, style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
                ]),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// A setting a teacher PIN locks: shown, not editable, until "Change…" and the PIN.
class _LockedField extends StatelessWidget {
  const _LockedField(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: c.sunk, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(6)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(c, size: 13, color: c.muted)),
    );
  }
}
