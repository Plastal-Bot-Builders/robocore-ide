// Projects page, card menu, Rename / Delete dialogs, the example preview and Settings → Reset all data.
import 'package:flutter/material.dart' show EditableText;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/main.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _start(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1800, 1100));
  late AppState state;
  await tester.runAsync(() async {
    state = AppState();
    await state.load();
  });
  state.setProfile(name: 'Thandi Mokoena', school: 'Grade 7B');
  await tester.pumpWidget(RoboCoreApp(state: state));
  await tester.pump(const Duration(milliseconds: 100));
  return state;
}

Future<void> _stop(WidgetTester tester, AppState state) async {
  state.sim.stop();
  await tester.pump(const Duration(seconds: 5));
  await tester.binding.setSurfaceSize(null);
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 50));

/// Opens the ⋮ menu on the card of [name].
Future<void> _cardMenu(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('More for $name'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('card menu: Duplicate, Rename…, Delete… (with its confirm dialog)', (tester) async {
    final s = await _start(tester);
    s.go(Screen.projects);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('5 of 5 projects · saved on this device'), findsOneWidget);
    expect(find.text('New project'), findsWidgets, reason: 'the page has its own New project button');

    await _cardMenu(tester, 'Blink LED');
    for (final item in ['Open', 'Rename…', 'Duplicate', 'Delete…']) {
      expect(find.text(item), findsOneWidget);
    }
    expect(find.textContaining(RegExp(r'^Download \.(ino|zip)$')), findsOneWidget);
    await tester.tap(find.text('Duplicate'));
    await _settle(tester); // the menu's layer goes one frame after it closes
    expect(find.text('Blink LED copy'), findsWidgets, reason: 'its card (and the sidebar, as the newest)');
    expect(find.text('6 of 6 projects · saved on this device'), findsOneWidget);

    await _cardMenu(tester, 'Blink LED copy');
    await tester.tap(find.text('Rename…'));
    await _settle(tester);
    expect(find.text('RENAME PROJECT'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'Blink LED');
    await tester.tap(find.text('Rename'));
    await tester.pump();
    expect(find.text('You already have a project called “Blink LED”.'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'Disco lights');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(find.text('Disco lights'), findsWidgets);

    await _cardMenu(tester, 'Disco lights');
    await tester.tap(find.text('Delete…'));
    await _settle(tester);
    expect(find.text('DELETE DISCO LIGHTS?'), findsOneWidget);
    expect(find.textContaining('You can’t undo it.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.text('Disco lights'), findsWidgets, reason: 'Cancel keeps it');

    await _cardMenu(tester, 'Disco lights');
    await tester.tap(find.text('Delete…'));
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.text('Disco lights'), findsNothing, reason: 'Enter is the main button');

    await _stop(tester, s);
  });

  testWidgets('no projects: the empty state', (tester) async {
    final s = await _start(tester);
    s.go(Screen.projects);
    for (final p in [...s.projects]) {
      s.deleteProject(p);
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('NO PROJECTS YET'), findsOneWidget);
    expect(find.text('Browse examples'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget, reason: 'status bar');
    await tester.tap(find.text('Browse examples'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(s.view, Screen.examples);
    await _stop(tester, s);
  });

  testWidgets('an example opens a preview first', (tester) async {
    final s = await _start(tester);
    s.go(Screen.examples);
    await tester.pump(const Duration(milliseconds: 100));
    final before = s.projects.length;
    // A C++ example: in tests the editor is the built-in Flutter one, whose blocks don't fit the test font.
    await tester.tap(find.text('RoboCore V2 board test'));
    await _settle(tester);
    expect(find.text('Open as new project'), findsOneWidget);
    expect(s.projects.length, before, reason: 'nothing is copied yet');
    await tester.tap(find.text('Open as new project'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(s.projects.length, before + 1);
    expect(s.view, Screen.editor);
    await _stop(tester, s);
  });

  testWidgets('Settings: explanation level, and Reset all data back to Welcome', (tester) async {
    final s = await _start(tester);
    expect(find.text('ROBOCORE V2 · GRADE 7B'), findsOneWidget, reason: 'the school on Home');
    s.go(Screen.settings);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Explanation level'), findsWidgets);
    s.updateSettings((x) => x.cogLevel = 'advanced');
    await tester.pump();
    expect(find.text('Advanced'), findsOneWidget);

    await tester.ensureVisible(find.text('Reset…'));
    await tester.tap(find.text('Reset…'));
    await _settle(tester);
    expect(find.text('RESET ALL DATA?'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('WELCOME TO ROBOCORE'), findsOneWidget);
    expect(s.projects, isEmpty);
    await _stop(tester, s);
  });

  testWidgets('status bar board opens Board Setup; Ctrl+B collapses the sidebar', (tester) async {
    final s = await _start(tester);
    await tester.tap(find.byTooltip('Board setup').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(s.view, Screen.board);
    expect(s.sideCollapsed, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.sideCollapsed, isTrue);
    await _stop(tester, s);
  });
}
