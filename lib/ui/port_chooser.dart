// The macOS app's port chooser (Connect on USB-C): the Mac's USB serial ports, one to pick. In a browser,
// Chrome shows its own.
import 'package:flutter/material.dart';

import '../theme.dart';
import 'dialogs.dart' show DialogFrame, RadioDot;
import 'widgets/common.dart';

Future<Map<String, Object?>?> showPortChooser(BuildContext context, List<Map<String, Object?>> ports) =>
    showDialog<Map<String, Object?>>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (_) => _PortChooser(ports: ports),
    );

class _PortChooser extends StatefulWidget {
  const _PortChooser({required this.ports});
  final List<Map<String, Object?>> ports;
  @override
  State<_PortChooser> createState() => _PortChooserState();
}

class _PortChooserState extends State<_PortChooser> {
  late Map<String, Object?>? _on = widget.ports.length == 1 ? widget.ports.first : null;

  static String _hex(Object? n) => n is int ? n.toRadixString(16).toUpperCase().padLeft(4, '0') : '????';

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    void pick() {
      if (_on != null) Navigator.of(context).pop(_on);
    }

    return DialogFrame(
      title: 'Connect a board',
      subtitle: widget.ports.isEmpty
          ? 'No USB board found. Plug it in with a data cable, then press Connect again.'
          : 'Pick the port your board is on.',
      onSubmit: pick,
      body: widget.ports.isEmpty
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final p in widget.ports) ...[
                Hover(
                  onTap: () => setState(() => _on = p),
                  builder: (context, h) {
                    final on = identical(p, _on);
                    final name = '${p['product'] ?? p['maker'] ?? 'USB serial device'}';
                    final path = '${p['path']}'.replaceFirst('/dev/', '');
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: on ? c.brandSoft : (h ? Color.lerp(c.sunk, c.ink, .06) : c.sunk),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        RcIcon('chip', size: 20, color: c.ink),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: tLabel(c)),
                            const SizedBox(height: 2),
                            Text('$path · ${_hex(p['vid'])}:${_hex(p['pid'])}', style: tCaption(c)),
                          ]),
                        ),
                        RadioDot(on: on),
                      ]),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ]),
      actions: [
        Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(context).pop()),
        if (widget.ports.isNotEmpty) Btn('Connect', icon: 'plug', kind: BtnKind.primary, onTap: _on == null ? null : pick),
      ],
    );
  }
}
