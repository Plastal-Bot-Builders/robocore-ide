// Compiles and briefly runs every example sketch in the simulator.
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/data/catalog.dart';
import 'package:robocore_ide/engine/compiler.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:robocore_ide/state/sim_board.dart';

void main() {
  for (final ex in kExamples) {
    test('example ${ex.id} compiles and runs', () async {
      final p = projectFrom(ex);
      p.syncCode();
      final r = compileSketch(
        files: [for (final f in p.files) SourceFile(f.name, f.content)],
        boardId: 'v2',
        installedLibs: {'esp32servo', 'neopixel'},
      );
      expect(r.errors.map((e) => '${e.line}: ${e.msg}').toList(), isEmpty);
      final lines = <String>[];
      final sim = SimBoard(onSerial: (t, d) => lines.add(t), onNote: (_) {});
      final run = sim.run(r, ex.name);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      sim.stop();
      final err = await run;
      expect(err?.msg, isNull);
    });
  }

  test('reports a missing loop()', () {
    final r = compileSketch(files: [const SourceFile('T.ino', 'void setup() {}')], boardId: 'v2', installedLibs: {});
    expect(r.errors.single.msg, contains("loop()"));
  });

  test('rgbLedWrite is ESP32-only', () {
    final r = compileSketch(
      files: [const SourceFile('T.ino', 'void setup() {}\nvoid loop() { rgbLedWrite(RGB_BUILTIN, 1, 2, 3); }')],
      boardId: 'uno',
      installedLibs: {},
    );
    expect(r.errors.any((e) => e.msg.contains('only available on ESP32')), isTrue);
  });

  test('blink toggles the LED', () async {
    final p = projectFrom(exampleById('blink'));
    p.syncCode();
    final r = compileSketch(files: [for (final f in p.files) SourceFile(f.name, f.content)], boardId: 'v2', installedLibs: {});
    final out = <String>[];
    final sim = SimBoard(onSerial: (t, d) => out.add(t), onNote: (_) {});
    final run = sim.run(r, 'Blink');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(sim.led, 1);
    expect(out, contains('RoboCore V2 ready'));
    sim.stop();
    await run;
  });
}
