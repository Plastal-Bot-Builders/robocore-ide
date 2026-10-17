import 'package:flutter/material.dart';

import '../../theme.dart';
import '../app_scope.dart';
import '../dialogs.dart' show RadioDot;
import '../widgets/common.dart';
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

    Widget theme(String key, String name, String desc, Color sw) {
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
            RadioDot(on: on),
            const SizedBox(width: 10),
            Container(
              width: 36,
              height: 24,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: sw, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
              alignment: Alignment.topCenter,
              child: Container(height: 6, color: kBrand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: tLabel(c)),
                Text(desc, style: tCaption(c), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
    }

    final phone = MediaQuery.sizeOf(context).width < 760;
    final themes = [
      theme('paper', 'Paper', 'The box colours', kCream),
      theme('navy', 'Navy', 'Dark, for low light', kNavy),
    ];

    return PageBody(children: [
      const PageHeader(title: 'Settings', subtitle: 'Saved automatically on this device.'),
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            card('Profile', [const _ProfileRow()]),
            const SizedBox(height: 20),
            card('Appearance', [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: phone
                    ? Column(children: [themes[0], const SizedBox(height: 12), themes[1]])
                    : Row(children: [Expanded(child: themes[0]), const SizedBox(width: 12), Expanded(child: themes[1])]),
              ),
            ]),
            const SizedBox(height: 20),
            card('Editor', [
              row(
                  'Font size',
                  RcSelect<int>(
                    value: st.fontSize,
                    width: 110,
                    label: 'Font size',
                    items: [for (final n in const [12, 13, 14, 15, 16, 18]) (n, '$n px')],
                    onChanged: (v) => s.updateSettings((x) => x.fontSize = v),
                  )),
              row('Autocomplete', RcSwitch(value: st.autocomplete, label: 'Autocomplete', onChanged: (v) => s.updateSettings((x) => x.autocomplete = v)),
                  hint: 'Suggest Arduino functions as you type.'),
              row('Word wrap', RcSwitch(value: st.wrap, label: 'Word wrap', onChanged: (v) => s.updateSettings((x) => x.wrap = v))),
            ]),
            const SizedBox(height: 20),
            card('Real board and upload', [const _CompileServerRow()]),
            const SizedBox(height: 20),
            card('General', [
              row('Language',
                  RcSelect<String>(value: st.lang, width: 130, label: 'Language', items: const [('English', 'English')], onChanged: (_) {})),
              row('Auto-save projects', RcSwitch(value: st.autosave, label: 'Auto-save projects', onChanged: (v) => s.updateSettings((x) => x.autosave = v)),
                  hint: 'Every 30 seconds and before upload.'),
            ]),
          ]),
        ),
      ),
    ]);
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
    _save();
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
    final r = _result;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Compile server', style: tLabel(c, w: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(
          'Verify and Upload use it to compile your C++ with arduino-cli and the esp32 core, then the IDE flashes '
          'the board over USB-C. Without it, Verify uses the built-in preview check and Upload runs the preview board. '
          'server/README.md shows how to run one (Docker, Render or Cloud Run).',
          style: tCaption(c),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Focus(
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
          const SizedBox(width: 8),
          Btn(_testing ? 'Testing…' : 'Test', height: 36, onTap: _testing ? null : _test),
        ]),
        if (r != null) ...[
          const SizedBox(height: 8),
          Text(r.$2, style: tCaption(c, color: r.$1 ? c.ok : c.err)),
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
    s.showToast('Profile saved.');
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
    final name = field('Name', _name, 'Your name', err: _error != null);
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
        if (_error != null) ...[const SizedBox(height: 6), Text(_error!, style: tCaption(c, color: c.err))],
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
