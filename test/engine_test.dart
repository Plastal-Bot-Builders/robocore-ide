// Compiles and briefly runs every example sketch in the simulator.
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/data/catalog.dart';
import 'package:robocore_ide/data/robocore_v2_examples.dart';
import 'package:robocore_ide/engine/codegen.dart';
import 'package:robocore_ide/engine/compiler.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:robocore_ide/state/sim_board.dart';

void main() {
  for (final ex in kExamples.where((e) => !e.realOnly)) {
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

  CompileResult check(String code, {String board = 'v2', Set<String> libs = const {}}) =>
      compileSketch(files: [SourceFile('T.ino', code)], boardId: board, installedLibs: libs);

  Future<List<String>> runFor(CompileResult r, {int ms = 300, void Function(SimBoard)? poke}) async {
    expect(r.errors.map((e) => '${e.line}: ${e.msg}').toList(), isEmpty);
    final out = <String>[];
    final sim = SimBoard(onSerial: (t, d) => out.add(t), onNote: (_) {});
    poke?.call(sim);
    final run = sim.run(r, 'T');
    await Future<void>.delayed(Duration(milliseconds: ms));
    sim.stop();
    final err = await run;
    if (err != null) out.add('ERR ${err.msg}');
    return out;
  }

  group('RoboCore V2', () {
    test('every V2 example is the library example from firmware/RoboCore/examples', () {
      for (final ex in kExamples.where((e) => e.v2 != null)) {
        expect(kV2ExampleCode.containsKey(ex.v2), isTrue, reason: '${ex.id} -> ${ex.v2}');
        final p = projectFrom(ex);
        if (p.codeEdited) expect(p.files.first.content, kV2ExampleCode[ex.v2], reason: ex.id);
      }
    });

    test('every library example except the board test passes the preview check and runs', () async {
      for (final e in kV2ExampleCode.entries.where((e) => e.key != 'BoardTest')) {
        final r = compileSketch(files: [SourceFile('${e.key}.ino', e.value)], boardId: 'v2', installedLibs: {'esp32servo'});
        expect(r.errors.map((x) => '${x.line}: ${x.msg}').toList(), isEmpty, reason: e.key);
        final sim = SimBoard(onSerial: (_, __) {}, onNote: (_) {});
        final run = sim.run(r, e.key);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        sim.stop();
        expect((await run)?.msg, isNull, reason: e.key);
      }
    });

    test('V2 projects use V2 pins, other boards keep theirs', () {
      final melodyV2 = projectFrom(exampleById('melody'), mode: 'blocks')..syncCode();
      expect(melodyV2.files.first.content, contains('tone(47,'));
      expect(melodyV2.files.first.content, isNot(contains('tone(8,')));
      final melodyUno = projectFrom(exampleById('melody'), board: 'uno', mode: 'blocks')..syncCode();
      expect(melodyUno.files.first.content, contains('tone(8,'));
      final trafficV2 = projectFrom(exampleById('traffic'), mode: 'blocks')..syncCode();
      expect(trafficV2.files.first.content, allOf(contains('digitalWrite(43,'), contains('digitalWrite(37,'), contains('digitalWrite(3,')));
      expect(projectFrom(exampleById('servo')).files.first.content, contains('RC_PIN_SERVO1'));
      expect(projectFrom(exampleById('servo'), board: 'devkit').files.first.content, contains('arm.attach(18)'));
      expect(projectFrom(exampleById('button')).files.first.content, contains('RC_PIN_USER_BUTTON'));
    });

    test('generic examples still compile on the boards they list', () {
      final boards = {'Uno': 'uno', 'ESP32': 'devkit'};
      for (final ex in kExamples.where((e) => !e.realOnly && e.code.isNotEmpty)) {
        for (final b in boards.entries) {
          if (!ex.boards.contains(b.key)) continue;
          final p = projectFrom(ex, board: b.value)..syncCode();
          final r = compileSketch(
            files: [for (final f in p.files) SourceFile(f.name, f.content)],
            boardId: b.value,
            installedLibs: {'esp32servo', 'neopixel'},
          );
          expect(r.errors.map((e) => e.msg).toList(), isEmpty, reason: '${ex.id} on ${b.value}');
        }
      }
    });

    test('the block pin list offers only free pins (and the buzzer for tones)', () {
      expect(pinOptions('v2'), ['3', '37', '43', '44', '38', '39', '35', '36']);
      expect(pinOptions('v2', tone: true).first, '47');
      for (final motorPin in ['11', '12', '13', '14', '8', '9']) {
        expect(pinOptions('v2', tone: true), isNot(contains(motorPin)));
      }
      expect(blockDefaults('tone', 'v2')['pin'], '47');
      expect(blockDefaults('tone', 'uno')['pin'], '8');
    });

    test('the USER button block reads IO42 without the internal pull-up', () {
      final code = genBlocks('B', [], [{'t': 'button'}, {'t': 'led', 'state': 'HIGH'}], board: 'v2');
      expect(code, contains('#define USER_BUTTON 42'));
      expect(code, contains('pinMode(USER_BUTTON, INPUT);'));
      final uno = genBlocks('B', [], [{'t': 'button'}], board: 'uno');
      expect(uno, contains('#define USER_BUTTON 0'));
      expect(uno, contains('INPUT_PULLUP'));
    });

    test('RC_PIN names come with the RoboCore headers', () {
      expect(check('#include <RoboCore.h>\nvoid setup() { pinMode(RC_PIN_BUZZER, OUTPUT); }\nvoid loop() {}').errors, isEmpty);
      expect(check('void setup() { pinMode(RC_PIN_BUZZER, OUTPUT); }\nvoid loop() {}').errors.single.msg,
          contains("'RC_PIN_BUZZER' was not declared"));
      expect(check('#include <RoboCoreV2Pins.h>\nvoid setup() { pinMode(RC_PIN_SERVO1, OUTPUT); }\nvoid loop() {}').errors, isEmpty);
    });

    test('the RoboCore library is refused on other boards', () {
      final r = check('#include <RoboCoreMotors.h>\nRoboCoreMotors m;\nvoid setup() {}\nvoid loop() {}', board: 'devkit');
      expect(r.errors.first.msg, contains('made for the RoboCore V2'));
    });

    test('RoboCore:: helpers need RoboCore.h and run in the preview', () async {
      expect(check('void setup() { Serial.println(RoboCore::batteryVolts(), 2); }\nvoid loop() {}').errors.single.msg,
          contains('#include <RoboCore.h>'));
      final out = await runFor(check('#include <RoboCore.h>\n'
          'void setup() { Serial.begin(115200); Serial.println(RoboCore::batteryVolts(), 2); RoboCore::rgb(1, 2, 3); }\n'
          'void loop() { delay(100); }'));
      expect(out.first, matches(RegExp(r'^3\.\d\d$')));
    });

    test('const char * parameters keep their text', () async {
      final out = await runFor(check('void say(const char *name) { Serial.println(name); }\n'
          'const char *greeting = "hi";\n'
          'void setup() { Serial.begin(115200); say("green"); char *x = "x"; Serial.println(x); Serial.println(greeting); }\n'
          'void loop() { delay(100); }'));
      expect(out.take(3).toList(), ['green', 'x', 'hi']);
    });

    test('USER on IO42 reads HIGH until pressed', () async {
      const code = '#include <RoboCore.h>\n'
          'void setup() { Serial.begin(115200); pinMode(RC_PIN_USER_BUTTON, INPUT); }\n'
          'void loop() { Serial.println(digitalRead(RC_PIN_USER_BUTTON)); delay(1000); }';
      expect((await runFor(check(code), ms: 150)).first, '1');
      expect((await runFor(check(code), ms: 150, poke: (s) => s.setUser(true))).first, '0');
    });

    test('LED_BUILTIN lights the RGB LED white on the V2', () async {
      final r = check('void setup() { pinMode(LED_BUILTIN, OUTPUT); digitalWrite(LED_BUILTIN, HIGH); }\nvoid loop() { delay(100); }');
      final sim = SimBoard(onSerial: (_, __) {}, onNote: (_) {});
      final run = sim.run(r, 'T');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sim.rgbColor, [255, 255, 255]);
      sim.stop();
      await run;
    });

    test('imu.begin() reports success in the preview', () async {
      final out = await runFor(check('#include <RoboCoreSensors.h>\nIMU imu;\n'
          'void setup() { Serial.begin(115200); if (!imu.begin()) Serial.println("IMU not found"); Serial.println("ok"); }\n'
          'void loop() { delay(100); }'));
      expect(out.first, 'ok');
    });
  });

  test('runaway recursion stops with a clear message instead of hanging', () async {
    final out = await runFor(check('int down(int n) { return down(n + 1); }\nvoid setup() { down(0); }\nvoid loop() {}'), ms: 2000);
    expect(out.last, allOf(contains('stack overflow'), contains('down()')));
  });

  test('bounded recursion still works', () async {
    final out = await runFor(check('int fact(int n) { if (n <= 1) return 1; return n * fact(n - 1); }\n'
        'void setup() { Serial.begin(115200); Serial.println(fact(10)); }\nvoid loop() { delay(100); }'));
    expect(out.first, '3628800');
  });
}
