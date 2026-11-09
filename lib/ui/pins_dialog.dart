// RoboCore V2 pins: which pin each part of the board is on, its name in RoboCore.h and where it comes out. The parts
// on the board have no IO numbers printed beside them (errata E-016), so this is where a student finds that the buzzer
// is IO47. Opened from Help › RoboCore V2 Pins (Mac menu bar), search, Board Setup and a pin block's right-click menu.
import 'package:flutter/material.dart';

import '../data/catalog.dart' show kV2Pins, kV2PartUses;
import '../theme.dart';
import 'dialogs.dart' show DialogFrame;
import 'widgets/common.dart';

Future<void> showV2PinsDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (_) => const _V2PinsDialog(),
    );

class _V2PinsDialog extends StatelessWidget {
  const _V2PinsDialog();

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 2),
          child: Text(title.toUpperCase(), style: tOverline(c)),
        );
    // One pin: the IO number, the part, then the code or the name and where it comes out, then what to know.
    Widget row(int io, String part, String detail, String note) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 52, child: Text('IO$io', style: tMono(c, size: 13, w: FontWeight.w600, height: 18 / 13))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(part, style: tBody(c, size: 13, w: FontWeight.w600, height: 18 / 13)),
                if (detail.isNotEmpty) Text(detail, style: tMono(c, size: 12, color: c.muted, height: 17 / 12)),
                if (note.isNotEmpty) Text(note, style: tCaption(c, color: c.faint)),
              ]),
            ),
          ]),
        );
    return DialogFrame(
      title: 'RoboCore V2 pins',
      subtitle: 'A pin number is the ESP32-S3’s GPIO number: IO47 is pin 47. In code, use the names from RoboCore.h.',
      body: SelectionArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'The parts on the board have no pin numbers printed beside them, so here they are. Uno habits don’t carry '
            'over: pin 8 is the I²C data line, and A0 means IO1, the motion sensor’s interrupt.',
            style: tBody(c, size: 13, height: 18 / 13),
          ),
          section('On the board'),
          for (final (part, io, code, note) in kV2PartUses) row(io, part, code, note),
          section('Every pin'),
          for (final p in kV2Pins)
            row(p.io, p.part.isEmpty ? 'Free for your own parts' : p.part,
                [p.cName, p.where].where((s) => s.isNotEmpty).join(' · '), p.note),
          const SizedBox(height: 12),
          Text(
            'Leave alone: IO19 and IO20 (USB), IO11 to IO18 and IO21 (the motors), IO8 and IO9 (add I²C parts to the bus '
            'instead). On the expansion headers, SDA, SCL, the IMU interrupt, USER, the buzzer and the LED data have no '
            'resistor: keep 5.5 V away from them.',
            style: tCaption(c, color: c.faint),
          ),
        ]),
      ),
      actions: [Btn('Done', kind: BtnKind.primary, onTap: () => Navigator.of(context).pop())],
    );
  }
}
