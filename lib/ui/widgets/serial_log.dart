// Serial log view (Serial Monitor page and editor console) and the send row.
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../state/models.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../cog/cog_panel.dart' show CogExplainButton;
import 'common.dart';

final _hiRe = RegExp('obstacle|warning|error', caseSensitive: false);

class SerialLog extends StatefulWidget {
  const SerialLog({super.key});
  @override
  State<SerialLog> createState() => _SerialLogState();
}

class _SerialLogState extends State<SerialLog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    return Container(
      color: c.surface,
      child: ValueListenableBuilder<int>(
        valueListenable: s.logTick,
        builder: (context, _, __) {
          final log = s.log.length > 1200 ? s.log.sublist(s.log.length - 1200) : s.log;
          if (s.autoscroll) _toEnd();
          // USB-C picked but no port open: say so, with Connect (SM-07). Earlier lines stay readable under a bar.
          final noBoard = s.onUsb && !s.usbOpen;
          if (log.isEmpty && noBoard) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('NO BOARD CONNECTED', style: tH2(c)),
                  const SizedBox(height: 10),
                  Text('Plug ${kBoards[s.boardId]!.name} in with a ${s.usbName} data cable, then press Connect.',
                      style: tBody(c, size: 13, color: c.muted), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Btn('Connect', icon: 'plug', kind: BtnKind.primary, onTap: s.connectUsb),
                ]),
              ),
            );
          }
          if (log.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Nothing yet. Upload a sketch, or send a message to the board.', style: tCaption(c)),
            );
          }
          final list = SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: log.length,
              itemExtent: 20,
              itemBuilder: (context, i) => _line(c, log[i], s.timestamps),
            ),
          );
          if (!noBoard) return list;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              decoration: BoxDecoration(color: c.sunk, border: Border(bottom: BorderSide(color: c.line2))),
              child: Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'No board connected. ', style: tLabel(c)),
                      TextSpan(text: 'Plug ${kBoards[s.boardId]!.name} in with a ${s.usbName} data cable, then press Connect.', style: tCaption(c)),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Btn('Connect', icon: 'plug', kind: BtnKind.primary, small: true, onTap: s.connectUsb),
              ]),
            ),
            Expanded(child: list),
          ]);
        },
      ),
    );
  }

  Widget _line(RC c, LogLine e, bool ts) {
    final hi = e.dir == 'out' && _hiRe.hasMatch(e.text);
    final base = tMono(c, size: 12, height: 18 / 12, color: c.sPlain);
    TextSpan body;
    switch (e.dir) {
      case 'in':
        body = TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(padding: const EdgeInsets.only(right: 6), child: RcIcon('arrow', size: 12, color: c.textBrand)),
          ),
          TextSpan(text: e.text, style: base.copyWith(color: c.ink, fontWeight: FontWeight.w700)),
        ]);
        break;
      case 'sys':
        body = TextSpan(text: e.text, style: base.copyWith(color: c.faint));
        break;
      case 'err':
        return _ErrorLine(time: ts ? e.t : null, text: e.text);
      default:
        body = TextSpan(text: e.text, style: hi ? base.copyWith(color: c.textBrand) : base);
    }
    return Text.rich(
      TextSpan(children: [
        if (ts) TextSpan(text: '${e.t}   ', style: base.copyWith(color: c.disabled)),
        body,
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}

/// Output panel (build messages).
/// An error line in a log: inverted (ink bar, light bold text), as in the design's Console Panel.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.time, required this.text, this.trailing});
  final String? time;
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final fg = c.dark ? kNavy : kCream;
    final base = tMono(c, size: 12, height: 18 / 12, color: fg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(3)),
      child: Row(children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              if (time != null) TextSpan(text: '$time   ', style: base.copyWith(color: fg.withValues(alpha: .75))),
              TextSpan(text: text, style: base.copyWith(fontWeight: FontWeight.w700)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

/// Output: build and upload messages, top down, following new lines. Errors are inverted lines (the first compile
/// error has Explain on it), tips and summaries the brand ochre, results bold (the design's Console Panel).
class OutputLog extends StatefulWidget {
  const OutputLog({super.key});
  @override
  State<OutputLog> createState() => _OutputLogState();
}

class _OutputLogState extends State<OutputLog> {
  final _scroll = ScrollController();
  int _seen = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final base = tMono(c, size: 12, height: 18 / 12, color: c.sPlain);
    if (s.output.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(s.onUsb ? 'Messages from Verify and Upload appear here.' : 'Upload runs the sketch on the preview board.',
            style: base.copyWith(color: c.faint)),
      );
    }
    if (s.output.length != _seen) {
      _seen = s.output.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    // Explain goes on the line of the first compile error.
    final problem = s.problems.where((e) => e.isError).firstOrNull;
    final explainAt =
        problem == null ? -1 : s.output.indexWhere((o) => o.kind == 'err' && o.text.startsWith('${problem.file}:${problem.line}'));
    return SelectionArea(
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          for (final (i, o) in s.output.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: o.kind == 'err'
                  ? _ErrorLine(
                      time: o.t,
                      text: o.text,
                      trailing: i == explainAt ? CogExplainButton(problem: problem!, onBar: true) : null,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${o.t}   ', style: base.copyWith(color: c.disabled)),
                        TextSpan(
                          text: o.text,
                          style: switch (o.kind) {
                            'info' || 'sys' => base.copyWith(color: c.faint),
                            'hint' => base.copyWith(color: c.textBrand),
                            'ok' => base.copyWith(color: c.ink, fontWeight: FontWeight.w700),
                            _ => base,
                          },
                        ),
                      ])),
                    ),
            ),
        ],
      ),
    );
  }
}

class SendRow extends StatefulWidget {
  const SendRow({super.key, required this.hint, this.big = false});
  final String hint;
  final bool big;
  @override
  State<SendRow> createState() => _SendRowState();
}

class _SendRowState extends State<SendRow> {
  final _c = TextEditingController();
  final _f = FocusNode();

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _send() {
    final v = _c.text;
    if (v.trim().isEmpty) return;
    AppScope.read(context).sendSerial(v);
    _c.clear();
    _f.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final h = widget.big ? 36.0 : 32.0;
    final phone = MediaQuery.sizeOf(context).width < 760;
    return Container(
      padding: widget.big ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line2))),
      child: Row(children: [
        Expanded(child: RcInput(controller: _c, focusNode: _f, hint: widget.hint, height: h, onSubmitted: (_) => _send())),
        if (widget.big && !phone) ...[
          const SizedBox(width: 8),
          RcSelect<String>(
            value: s.lineEnd,
            height: h,
            width: 150,
            label: 'Line ending',
            items: const [('nl', 'New line'), ('none', 'No line ending'), ('cr', 'Carriage return'), ('both', 'Both NL & CR')],
            onChanged: (v) => s.setSerialOption(ending: v),
          ),
        ],
        const SizedBox(width: 8),
        Btn('Send', kind: widget.big ? BtnKind.primary : BtnKind.outline, height: h, onTap: _send),
      ]),
    );
  }
}
