// New project and Project settings dialogs.
import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'widgets/common.dart';

Future<void> showNewProjectDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (_) => AppScope(notifier: AppScope.read(context), child: const _NewProjectDialog()),
    );

Future<void> showProjectSettingsDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (_) => AppScope(notifier: AppScope.read(context), child: const _ProjectSettingsDialog()),
    );

class DialogFrame extends StatelessWidget {
  const DialogFrame({super.key, required this.title, this.subtitle, required this.body, required this.actions});
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 500,
        decoration: BoxDecoration(
          color: c.raised,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(12),
          boxShadow: modalShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title.toUpperCase(), style: tH2(c)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
                  ],
                ]),
              ),
              IconBtn('x', onTap: () => Navigator.of(context).pop(), tip: 'Close'),
            ]),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 20), child: body)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]],
            ]),
          ),
        ]),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: tLabel(c, color: c.muted, w: FontWeight.w500)));
  }
}

List<(String, String)> get _boardItems => [for (final id in kBoardOrder) (id, kBoards[id]!.full)];

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();
  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _name = TextEditingController();
  String mode = 'blocks';
  String? board;
  String? error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final s = AppScope.read(context);
    final e = s.validateName(_name.text);
    if (e != null) {
      setState(() => error = e);
      return;
    }
    Navigator.of(context).pop();
    s.createProject(name: _name.text, mode: mode, boardId: board ?? s.board);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    return DialogFrame(
      title: 'New project',
      subtitle: 'You can switch between Blocks and Code at any time.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FieldLabel('Project name'),
        RcInput(
          controller: _name,
          hint: 'Obstacle avoider',
          height: 36,
          fontSize: 14,
          autofocus: true,
          error: error != null,
          onChanged: (_) => setState(() => error = null),
          onSubmitted: (_) => _create(),
        ),
        if (error != null) ...[const SizedBox(height: 6), Text(error!, style: tCaption(c, color: c.err))],
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, k) {
          final narrow = k.maxWidth < 360;
          final a = _ModeOption(icon: 'blocks', title: 'Blocks', sub: 'Drag and drop', on: mode == 'blocks', onTap: () => setState(() => mode = 'blocks'));
          final b = _ModeOption(icon: 'code', title: 'C++', sub: 'Arduino-style C++ code', on: mode == 'code', onTap: () => setState(() => mode = 'code'));
          return narrow
              ? Column(children: [a, const SizedBox(height: 12), b])
              : Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);
        }),
        const SizedBox(height: 16),
        const FieldLabel('Board'),
        RcSelect<String>(
          value: board ?? s.board,
          height: 36,
          width: double.infinity,
          items: _boardItems,
          label: 'Board',
          onChanged: (v) => setState(() => board = v),
        ),
      ]),
      actions: [
        Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(context).pop()),
        Btn('Create project', icon: 'plus', kind: BtnKind.primary, onTap: _create),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.icon, required this.title, required this.sub, required this.on, required this.onTap});
  final String icon, title, sub;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Semantics(
      selected: on,
      child: Hover(
        onTap: onTap,
        builder: (context, h) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: on ? c.brandSoft : (c.dark ? c.sunk : Colors.white),
            border: Border.all(color: on ? c.ink : c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RcIcon(icon, size: 20, color: c.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tLabel(c)),
                const SizedBox(height: 2),
                Text(sub, style: tCaption(c)),
              ]),
            ),
            RadioDot(on: on),
          ]),
        ),
      ),
    );
  }
}

class RadioDot extends StatelessWidget {
  const RadioDot({super.key, required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: on ? kNavy : const Color(0xFFA4A8AD), width: on ? 1.5 : 1),
      ),
      alignment: Alignment.center,
      child: on ? Container(width: 9, height: 9, decoration: const BoxDecoration(color: kNavy, shape: BoxShape.circle)) : null,
    );
  }
}

class _ProjectSettingsDialog extends StatefulWidget {
  const _ProjectSettingsDialog();
  @override
  State<_ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<_ProjectSettingsDialog> {
  late final TextEditingController _name;
  late String board;
  late bool autosave;
  String? error;
  bool confirmDelete = false;

  @override
  void initState() {
    super.initState();
    final p = AppScope.read(context).cur!;
    _name = TextEditingController(text: p.name);
    board = p.board;
    autosave = p.autosave;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final s = AppScope.read(context);
    final p = s.cur;
    if (p == null) return;
    final e = s.validateName(_name.text);
    if (e != null) {
      setState(() => error = e);
      return;
    }
    Navigator.of(context).pop();
    s.saveProjectSettings(p, name: _name.text, boardId: board, autosave: autosave);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final p = s.cur;
    if (p == null) return const SizedBox.shrink();
    return DialogFrame(
      title: 'Project settings',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FieldLabel('Name'),
        RcInput(controller: _name, height: 36, fontSize: 14, error: error != null, onSubmitted: (_) => _save()),
        const SizedBox(height: 6),
        Text(error ?? 'Letters, numbers and spaces.', style: tCaption(c, color: error != null ? c.err : c.faint)),
        const SizedBox(height: 16),
        const FieldLabel('Board'),
        RcSelect<String>(value: board, height: 36, width: double.infinity, items: _boardItems, onChanged: (v) => setState(() => board = v)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Auto-save', style: tLabel(c, w: FontWeight.w500)),
              const SizedBox(height: 2),
              Text('Saves a moment after each change and before upload.', style: tCaption(c)),
            ]),
          ),
          RcSwitch(value: autosave, onChanged: (v) => setState(() => autosave = v), label: 'Auto-save'),
        ]),
      ]),
      actions: [
        Btn(confirmDelete ? 'Click again to delete' : 'Delete project', icon: 'trash', kind: BtnKind.danger, onTap: () {
          if (!confirmDelete) {
            setState(() => confirmDelete = true);
            return;
          }
          Navigator.of(context).pop();
          s.deleteProject(p);
        }),
        const Spacer(),
        Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(context).pop()),
        Btn('Save', kind: BtnKind.primary, onTap: _save),
      ],
    );
  }
}
