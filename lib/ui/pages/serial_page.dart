import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../shell.dart' show ConnStatus;
import '../widgets/common.dart';
import '../widgets/serial_log.dart';

class SerialPage extends StatelessWidget {
  const SerialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;
    Widget sw(String label, bool v, ValueChanged<bool> f) => Row(mainAxisSize: MainAxisSize.min, children: [
          RcSwitch(value: v, onChanged: f, label: label),
          const SizedBox(width: 8),
          Text(label, style: tLabel(c, w: FontWeight.w500)),
        ]);
    return Padding(
      padding: phone ? const EdgeInsets.fromLTRB(16, 20, 16, 16) : const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'Serial Monitor',
          subtitle: s.onUsb
              ? 'Read and send text over the ${kBoards[s.boardId]!.name}’s ${s.usbName} port.'
              : 'Read and send text to the preview board. Pick ${s.usbName} to talk to the real one.',
          trailing: ConnStatus(connected: s.linked),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: RcCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    RcSelect<String>(
                      value: s.port,
                      width: phone ? 200 : 240,
                      label: 'Port',
                      items: s.portItems,
                      onChanged: (v) => s.setPort(v),
                    ),
                    if (s.onUsb && s.usbOpen) Btn('Reset board', kind: BtnKind.plain, onTap: s.resetUsbBoard),
                    RcSelect<int>(
                      value: s.baud,
                      width: 128,
                      label: 'Baud rate',
                      items: const [(9600, '9600 baud'), (57600, '57600 baud'), (115200, '115200 baud'), (230400, '230400 baud')],
                      onChanged: s.setBaud,
                    ),
                    if (!phone) const SizedBox(width: 24),
                    sw('Timestamps', s.timestamps, (v) => s.setSerialOption(ts: v)),
                    sw('Autoscroll', s.autoscroll, (v) => s.setSerialOption(scroll: v)),
                    IconBtn('trash', onTap: s.clearLog, tip: 'Clear output'),
                  ],
                ),
              ),
              const Expanded(child: SerialLog()),
              const SendRow(hint: 'Type a message and press Enter', big: true),
            ]),
          ),
        ),
      ]),
    );
  }
}
