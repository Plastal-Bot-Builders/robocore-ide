// Serial log view (Serial Monitor page and editor console) and the send row.
import 'package:flutter/material.dart';

import '../../state/models.dart';
import '../../theme.dart';
import '../app_scope.dart';
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
          if (log.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Nothing yet. Upload a sketch, or send a message to the board.', style: tCaption(c)),
            );
          }
          return SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: log.length,
              itemExtent: 20,
              itemBuilder: (context, i) => _line(c, log[i], s.timestamps),
            ),
          );
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
        body = TextSpan(text: e.text, style: base.copyWith(color: c.err));
        break;
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
class OutputLog extends StatelessWidget {
  const OutputLog({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    if (s.output.isEmpty) {
      return Padding(padding: const EdgeInsets.all(16), child: Text('Verify or upload to see build output here.', style: tCaption(c)));
    }
    final base = tMono(c, size: 12, height: 18 / 12, color: c.sPlain);
    return SelectionArea(
      child: ListView(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          for (final o in s.output.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${o.t}   ', style: base.copyWith(color: c.disabled)),
                TextSpan(
                  text: o.text,
                  style: switch (o.kind) {
                    'info' => base.copyWith(color: c.faint),
                    'sys' => base.copyWith(color: c.faint),
                    'err' => base.copyWith(color: c.err),
                    'ok' => base.copyWith(color: c.ink, fontWeight: FontWeight.w700),
                    _ => base,
                  },
                ),
              ])),
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
