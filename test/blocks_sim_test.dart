// The hardware-first blocks in the preview board: the C++ the Blockly generator writes for every toolbox
// block (test/fixtures/all_blocks.ino, made by web/robocore_editors.js) checks and runs, and the robot
// moves and turns as far as it would on the real one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/engine/compiler.dart';
import 'package:robocore_ide/state/sim_board.dart';

CompileResult _check(String code) => compileSketch(files: [SourceFile('T.ino', code)], boardId: 'v2', installedLibs: const {});

/// Runs [code] until it prints "done" (or [limit] passes); returns the lines it printed and the notes.
Future<(List<String>, List<String>, SimBoard)> _run(String code, {Duration limit = const Duration(seconds: 6)}) async {
  final r = _check(code);
  expect(r.errors.map((e) => '${e.line}: ${e.msg}').toList(), isEmpty);
  final out = <String>[], notes = <String>[];
  final sim = SimBoard(onSerial: (t, d) => out.add(t), onNote: notes.add);
  final run = sim.run(r, 'T');
  final sw = Stopwatch()..start();
  while (!out.contains('done') && sw.elapsed < limit && sim.running) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  sim.stop();
  final err = await run;
  expect(err?.msg, isNull);
  return (out, notes, sim);
}

void main() {
  test('every toolbox block: the generated sketch checks and runs, with no unsupported calls', () async {
    final code = File('test/fixtures/all_blocks.ino').readAsStringSync();
    final (_, notes, _) = await _run(code, limit: const Duration(seconds: 3));
    expect(notes, isEmpty);
  });

  test('move, turn and distance in the preview board', () async {
    final (out, notes, sim) = await _run('''
#include <RoboCore.h>
RoboCoreMotors motors;
IMU imu;
RoboCoreDrive robot(motors, imu);
void setup() {
  Serial.begin(115200);
  robot.setSpeed(100);
  robot.move(9.4, CM);
  Serial.println(robot.distanceCm());
  robot.move(-0.5, ROTATIONS);
  Serial.println(robot.distanceCm());
  imu.resetYaw();
  robot.turn(90);
  Serial.println(imu.yawDeg());
  motors.resetPosition(LEFT);
  motors.run(LEFT, 180, DEGREES, 100);
  Serial.println(motors.positionDeg(LEFT));
  motors.start(RIGHT, 40);
  Serial.println(motors.speedPercent(RIGHT));
  robot.stop();
  Serial.println("done");
}
void loop() {}
''');
    expect(notes, isEmpty);
    final v = out.take(5).map(double.parse).toList();
    expect(v[0], closeTo(9.4, 1.0), reason: 'moved 9.4 cm');
    expect(v[1], closeTo(0, 1.5), reason: 'and back half a turn');
    expect(v[2], closeTo(90, 8), reason: 'turned right 90°');
    expect(v[3], closeTo(180, 15), reason: 'left wheel half a turn');
    expect(v[4], 40);
    expect(sim.motorSpeeds, [0, 0]);
  });

  test('RoboCore helpers: timer, battery %, LED brightness, edges, stop program', () async {
    final (out, notes, sim) = await _run('''
#include <RoboCore.h>
RoboCoreEdge when1;
int n = 0;
void setup() {
  Serial.begin(115200);
  RoboCore::resetTimer();
  Serial.println(RoboCore::timerPassed(0.2));
  delay(300);
  Serial.println(RoboCore::timerPassed(0.2));
  Serial.println(RoboCore::timerPassed(0.2));
  int pct = RoboCore::batteryPercent();
  Serial.println(pct > 0 && pct <= 100);
  RoboCore::rgb(200, 100, 0);
  RoboCore::ledBrightness(50);
  Serial.println(when1.rose(false));
  Serial.println(when1.rose(true));
  Serial.println(when1.rose(true));
  Serial.println("done");
  RoboCore::stopProgram();
  Serial.println("not reached");
}
void loop() {}
''');
    expect(notes, isEmpty);
    expect(out.take(7).toList(), ['0', '1', '0', '1', '0', '1', '0']);
    expect(sim.rgbColor, [100, 50, 0]);
    expect(out, isNot(contains('not reached')));
  });
}
