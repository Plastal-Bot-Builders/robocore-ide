// The animated app icon (lib/ui/widgets/geared_ring.dart) must draw exactly the master Geared Ring
// (tools/app_icon/concepts.js) at every angle. The fixture comes from: node tools/app_icon/spin_fixture.js
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/ui/widgets/geared_ring.dart';

/// "M1 2 L3 4 C… Z" → [['M', 1.0, 2.0], ['L', 3.0, 4.0], …, ['Z']]
List<List<Object>> parsePath(String d) {
  final out = <List<Object>>[];
  for (final m in RegExp(r'([MLCZ])([^MLCZ]*)').allMatches(d)) {
    final nums = RegExp(r'-?\d*\.?\d+(?:e[-+]?\d+)?').allMatches(m[2]!).map((n) => double.parse(n[0]!));
    out.add([m[1]!, ...nums]);
  }
  return out;
}

void main() {
  final fixture = (jsonDecode(File('test/fixtures/geared_ring_spin.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  for (final f in fixture) {
    final spin = (f['spin'] as num).toDouble();
    test('matches the master glyph at spin $spin°', () {
      final want = parsePath(f['d'] as String);
      final got = GearedRing.commands(spin);
      expect(got.length, want.length, reason: 'number of path commands');
      for (var i = 0; i < want.length; i++) {
        expect(got[i][0], want[i][0], reason: 'command $i');
        expect(got[i].length, want[i].length, reason: 'command $i arguments');
        for (var k = 1; k < want[i].length; k++) {
          // the master rounds to 2 decimals
          expect((got[i][k] as double) - (want[i][k] as double), closeTo(0, .011), reason: 'command $i value $k');
        }
      }
    });
  }

  test('one tooth of spin gives the same outline again', () {
    final a = GearedRing.glyph(0).getBounds(), b = GearedRing.glyph(-GearedRing.toothPitch).getBounds();
    expect(a.left, closeTo(b.left, .01));
    expect(a.top, closeTo(b.top, .01));
    expect(a.right, closeTo(b.right, .01));
    expect(a.bottom, closeTo(b.bottom, .01));
  });

  test('the glyph stays inside the Rounded plate at every angle', () {
    for (var spin = 0.0; spin > -GearedRing.toothPitch; spin -= 1.5) {
      final r = GearedRing.glyph(spin).getBounds();
      // the glyph is scaled by roundedScale about the centre of the 1024 canvas
      const k = GearedRing.roundedScale;
      expect(512 + (r.left - 512) * k, greaterThan(0));
      expect(512 + (r.right - 512) * k, lessThan(1024));
    }
  });

  testWidgets('the icon painter draws', (tester) async {
    await tester.pumpWidget(Center(
      child: CustomPaint(size: const Size.square(96), painter: GearedRingIconPainter(spin: -7.5)),
    ));
    expect(tester.takeException(), isNull);
  });
}
