import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../shell.dart' show ConnStatus;
import '../widgets/common.dart';
import 'home_page.dart';

/// RoboCore V2 pins (Rev 2.0 schematic), grouped for the pin map card.
const _v2PinRows = [
  ('Motor 1 (left)', 'IN1 IO${RoboCoreV2Pins.motor1In1} · IN2 IO${RoboCoreV2Pins.motor1In2} · encoder IO${RoboCoreV2Pins.enc1A}/IO${RoboCoreV2Pins.enc1B} · current IO${RoboCoreV2Pins.motor1Isense}'),
  ('Motor 2 (right)', 'IN1 IO${RoboCoreV2Pins.motor2In1} · IN2 IO${RoboCoreV2Pins.motor2In2} · encoder IO${RoboCoreV2Pins.enc2A}/IO${RoboCoreV2Pins.enc2B} · current IO${RoboCoreV2Pins.motor2Isense}'),
  ('Motor fault', 'nFAULT IO${RoboCoreV2Pins.motorNfault} (LOW = fault)'),
  ('Ultrasonic', 'TRIG IO${RoboCoreV2Pins.sonarTrig} · ECHO IO${RoboCoreV2Pins.sonarEcho}'),
  ('Line sensor', 'left IO${RoboCoreV2Pins.lineLeft} · centre IO${RoboCoreV2Pins.lineCentre} · right IO${RoboCoreV2Pins.lineRight}'),
  ('IMU', 'LSM6DSOX on I²C SDA IO${RoboCoreV2Pins.i2cSda} / SCL IO${RoboCoreV2Pins.i2cScl} · INT1 IO${RoboCoreV2Pins.imuInt1}'),
  ('Servos', '1 IO${RoboCoreV2Pins.servo1} · 2 IO${RoboCoreV2Pins.servo2} · 3 IO${RoboCoreV2Pins.servo3} · 4 IO${RoboCoreV2Pins.servo4}'),
  ('Buttons', 'USER IO${RoboCoreV2Pins.userButton} · BOOT IO${RoboCoreV2Pins.bootButton} (LOW when pressed)'),
  ('Buzzer · RGB', 'buzzer IO${RoboCoreV2Pins.buzzer} · RGB LED IO${RoboCoreV2Pins.rgbLed}'),
  ('Battery', 'IO${RoboCoreV2Pins.batterySense} reads battery ÷ 2'),
  ('Free pins', 'IO3, IO37, IO43 (TX), IO44 (RX) on the expansion headers'),
];

class BoardPage extends StatelessWidget {
  const BoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final sel = s.bsel ?? s.board;
    final b = kBoards[sel]!;
    final active = sel == s.board;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;

    final list = RcCard(
      padding: const EdgeInsets.all(8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final id in kBoardOrder)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Hover(
              onTap: () => s.selectBoardDetail(id),
              builder: (context, h) => Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: id == sel ? c.brandSoft : (h ? c.sunk : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  RcIcon('chip', size: 18, color: c.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(kBoards[id]!.name, style: tLabel(c)),
                      const SizedBox(height: 2),
                      Text(kBoards[id]!.spec, style: tCaption(c), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  if (id == s.board && id != sel)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
                      child: Text('Default', style: tCaption(c).copyWith(fontSize: 11)),
                    ),
                ]),
              ),
            ),
          ),
      ]),
    );

    final specs = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in b.details)
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 84, child: Text(d[0], style: tCaption(c))),
            Expanded(child: Text(d[1], style: tBody(c, size: 13, height: 18 / 13))),
          ]),
        ),
    ]);

    final detail = RcCard(
      padding: EdgeInsets.all(width < 760 ? 16 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
              Text(b.name.toUpperCase(), style: tH1(c)),
              Badge2(b.rev, bg: kBrand, fg: kNavy),
            ]),
          ),
          const SizedBox(width: 12),
          active
              ? ConnStatus(connected: s.linked)
              : Btn('Use this board', kind: BtnKind.primary, small: true, onTap: () => s.setDefaultBoard(sel)),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, k) {
          final art = b.id == 'v2' ? Image.asset('assets/images/board.png', width: 380, filterQuality: FilterQuality.medium) : null;
          if (art == null) return specs;
          if (k.maxWidth < 700) return Column(children: [art, const SizedBox(height: 16), specs]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 380, child: art),
            const SizedBox(width: 32),
            Expanded(child: specs),
          ]);
        }),
      ]),
    );

    Widget field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: tLabel(c, color: c.muted, w: FontWeight.w500)),
          const SizedBox(height: 6),
          child,
        ]);

    final connection = RcCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('CONNECTION', style: tH2(c)),
        const SizedBox(height: 14),
        field('Port', RcSelect<String>(value: s.port, height: 36, width: double.infinity, items: s.portItems, onChanged: (v) => s.setPort(v))),
        const SizedBox(height: 14),
        field(
            'Baud rate',
            RcSelect<int>(
                value: s.baud,
                height: 36,
                width: double.infinity,
                items: const [(9600, '9600'), (57600, '57600'), (115200, '115200'), (230400, '230400')],
                onChanged: s.setBaud)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn(s.busy == 'test' ? 'Testing…' : 'Test connection', onTap: s.busy == null ? s.testConnection : null),
          s.linked
              ? Btn('Disconnect', kind: BtnKind.plain, onTap: s.busy == 'test' ? null : s.disconnect)
              : Btn(s.onUsb ? 'Connect USB-C' : 'Connect', kind: BtnKind.primary, onTap: s.connect),
          if (s.onUsb && s.usbOpen) Btn('Reset board', kind: BtnKind.plain, onTap: s.busy == null ? s.resetUsbBoard : null),
          if (!s.onUsb) Btn('Use a real board (USB-C)', kind: BtnKind.plain, onTap: () => s.setPort(kPortUsb)),
        ]),
        const SizedBox(height: 10),
        Text(
          !s.usb.supported
              ? 'Real boards connect through Web Serial: open the web app in Chrome or Edge on a computer.'
              : s.onUsb
                  ? 'Plug the RoboCore into USB-C, press Connect and pick “USB JTAG/serial debug unit” (ESP32-S3). '
                      'It reconnects by itself after an upload or if you unplug it.'
                  : 'Sketches run on the preview board. Pick USB-C to use the real RoboCore.',
          style: tCaption(c),
        ),
        if (s.conn != null) ...[
          const SizedBox(height: 10),
          Text(s.conn!.text,
              style: tBody(c, size: 13, color: s.conn!.kind == 'ok' ? c.ok : (s.conn!.kind == 'err' ? c.err : c.muted))),
        ],
      ]),
    );

    final parts = b.id == 'v2'
        ? const ['8 MB · 3 MB app / 1.5 MB SPIFFS', '8 MB · 6 MB app / no SPIFFS']
        : const ['4 MB · 1.2 MB app / 1.5 MB SPIFFS', '4 MB · 3 MB app / no OTA'];
    final build = RcCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('BUILD OPTIONS', style: tH2(c)),
        const SizedBox(height: 14),
        if (b.arch == 'esp32') ...[
          field(
              'CPU frequency',
              RcSelect<String>(
                  value: s.cpu,
                  height: 36,
                  width: double.infinity,
                  items: const [('240 MHz', '240 MHz'), ('160 MHz', '160 MHz'), ('80 MHz', '80 MHz')],
                  onChanged: s.setCpu)),
          const SizedBox(height: 14),
          field(
              'Partition scheme',
              RcSelect<String>(
                  value: parts.contains(s.partition) ? s.partition : parts.first,
                  height: 36,
                  width: double.infinity,
                  items: [for (final p in parts) (p, p)],
                  onChanged: s.setPartition)),
        ] else
          Text('The Uno has no build options to change.', style: tBody(c, size: 13, color: c.muted)),
      ]),
    );

    final pinMap = b.id == 'v2'
        ? RcCard(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('PIN MAP (REV 2.0)', style: tH2(c)),
              const SizedBox(height: 4),
              Text('From the schematic. Sketches use these names from RoboCore.h, e.g. RC_PIN_BUZZER.', style: tCaption(c)),
              const SizedBox(height: 12),
              for (final r in _v2PinRows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 120, child: Text(r.$1, style: tCaption(c))),
                    Expanded(child: Text(r.$2, style: tMono(c, size: 12, height: 18 / 12))),
                  ]),
                ),
            ]),
          )
        : null;

    final cfg = width >= 900
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: connection),
            const SizedBox(width: 24),
            Expanded(child: build),
          ])
        : Column(children: [connection, const SizedBox(height: 24), build]);

    return PageBody(children: [
      const PageHeader(title: 'Board Setup', subtitle: 'Choose a board, connect it over USB and set build options.'),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 280, child: list),
          const SizedBox(width: 24),
          Expanded(
              child: Column(children: [
            detail,
            const SizedBox(height: 24),
            cfg,
            if (pinMap != null) ...[const SizedBox(height: 24), pinMap],
          ])),
        ])
      else ...[
        list,
        detail,
        cfg,
        if (pinMap != null) pinMap,
      ],
    ]);
  }
}
