// Code editor extras: the API list behind suggestions, hints and hovers; new tabs; the missing-library check;
// the banner over the code and the “Delete all N blocks?” dialog.
import 'package:flutter/material.dart' show EditableText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/data/arduino_api.dart';
import 'package:robocore_ide/engine/compiler.dart';
import 'package:robocore_ide/main.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _state() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState();
  await s.load();
  s.sim.stop();
  s.setProfile(name: 'Thandi Mokoena');
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the API list: unique names, plain docs, functions with (params), reference links where they exist', () {
    expect(kApi.map((e) => e.name).toSet(), hasLength(kApi.length));
    for (final e in kApi) {
      expect(e.doc.trim(), isNotEmpty, reason: e.name);
      expect(e.params.isEmpty || (e.params.startsWith('(') && e.params.endsWith(')')), isTrue, reason: e.name);
      if (e.url != null) expect(e.url, startsWith('https://docs.arduino.cc/language-reference/en/functions/'));
    }
    for (final n in ['digitalWrite', 'Serial.println', 'motors.drive', 'sonar.distanceCm', 'RoboCore::rgb', 'imu.tiltDeg']) {
      expect(kApi.any((e) => e.name == n), isTrue, reason: n);
    }
  });

  test('new tabs: name rules, unique, and the tab opens', () async {
    final s = await _state();
    final p = s.projects.first;
    s.openProject(p.id);
    expect(s.validateFileName(p, ''), isNotNull);
    expect(s.validateFileName(p, 'motors'), isNotNull, reason: 'needs an extension');
    expect(s.validateFileName(p, '2motors.h'), isNotNull, reason: 'starts with a letter');
    expect(s.validateFileName(p, p.files.first.name.toLowerCase()), contains('already has'));
    expect(s.validateFileName(p, 'motors.h'), isNull);
    s.addFile(p, 'motors.h');
    expect(p.files.last.name, 'motors.h');
    expect(p.files.last.content, contains('#pragma once'));
    expect(s.file, p.files.length - 1);
    expect(p.mode, 'code');
  });

  test('a library that is not installed is reported before compiling (L-04)', () {
    const sketch = SourceFile('Ping.ino', '#include <NewPing.h>\n#include <RoboCore.h>\nvoid setup() {}\nvoid loop() {}\n');
    final missing = missingLibraries([sketch], {'esp32servo'});
    expect(missing, hasLength(1));
    expect(missing.single.line, 1);
    expect(missing.single.msg, 'NewPing is not installed. Install it in Libraries.');
    expect(missingLibraries([sketch], {'newping'}), isEmpty);
  });

  testWidgets('the banner over the code, and Rebuild from blocks asks first', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1800, 1100));
    late AppState s;
    await tester.runAsync(() async {
      s = AppState();
      await s.load();
    });
    s.setProfile(name: 'Thandi Mokoena');
    await tester.pumpWidget(RoboCoreApp(state: s));
    await tester.pump(const Duration(milliseconds: 100));

    // A C++ project.
    final cpp = s.projects.firstWhere((p) => p.mode == 'code' && p.setup.isEmpty && p.loop.isEmpty && p.blockly == null);
    s.openProject(cpp.id);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('C++ project. Ctrl+Space shows suggestions'), findsOneWidget);

    // A blocks project in C++: generated, then edited by hand.
    final blocks = s.projects.firstWhere((p) => p.setup.isNotEmpty || p.loop.isNotEmpty);
    s.openProject(blocks.id);
    s.setMode('code');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Generated from your blocks.'), findsOneWidget);
    s.editCode('${blocks.files.first.content}\n// mine\n');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('You edited this file, so the blocks no longer change it.'), findsOneWidget);
    await tester.tap(find.text('Rebuild from blocks'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('REBUILD THE CODE FROM YOUR BLOCKS?'), findsOneWidget);
    await tester.tap(find.text('Rebuild'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(blocks.codeEdited, isFalse);

    // + adds a tab.
    await tester.tap(find.byTooltip('New tab'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(EditableText).last, 'motors.h');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(blocks.files.last.name, 'motors.h');

    s.sim.stop();
    await tester.pump(const Duration(seconds: 5));
    await tester.binding.setSurfaceSize(null);
  });
}
