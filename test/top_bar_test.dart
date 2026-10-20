// Top bar: the buttons stay at the right edge in the editor, and the account button opens the account menu (G-10).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/main.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _start(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1800, 1000));
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
  await tester.pump(const Duration(seconds: 3));
  await tester.binding.setSurfaceSize(null);
}

void main() {
  testWidgets('in the editor the top-bar buttons stay at the right edge, as on Home', (tester) async {
    final state = await _start(tester);
    final onHome = tester.getTopRight(find.text('TM')).dx;
    final gearOnHome = tester.getCenter(find.byTooltip('Settings').first).dx;

    // A C++ project: in tests the editor is the built-in Flutter one (no Blockly), whose blocks don't fit the test font.
    state.openProject(state.sortedProjects.firstWhere((p) => p.mode == 'code').id);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Upload'), findsOneWidget);
    // The project name used to share the free space with a Spacer, which pushed these about 300 px left.
    expect(tester.getTopRight(find.text('TM')).dx, closeTo(onHome, 1));
    expect(tester.getCenter(find.byTooltip('Settings').first).dx, closeTo(gearOnHome, 1));
    expect(1800 - tester.getTopRight(find.text('TM')).dx, lessThan(40));

    await _stop(tester, state);
  });

  testWidgets('the account button opens a menu; the gear opens Settings', (tester) async {
    final state = await _start(tester);

    await tester.tap(find.text('TM'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Thandi Mokoena'), findsOneWidget);
    expect(find.text('Grade 7B · this device'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(state.view, Screen.home, reason: 'the avatar no longer jumps straight to Settings');

    // Esc closes the menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.text('Edit profile'), findsNothing);

    // Keyboard shortcuts and About open dialogs.
    await tester.tap(find.text('TM'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Keyboard shortcuts'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('KEYBOARD SHORTCUTS'), findsOneWidget);
    expect(find.text('Ask Cog'), findsWidgets);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    await tester.tap(find.text('TM'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('About RoboCore IDE'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('ABOUT ROBOCORE IDE'), findsOneWidget);
    expect(find.textContaining('Blockly'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    // Edit profile goes to Settings, where Profile is the first card.
    await tester.tap(find.text('TM'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Edit profile'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.view, Screen.settings);
    expect(find.text('PROFILE'), findsOneWidget);

    // The gear goes straight to Settings.
    state.go(Screen.home);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.view, Screen.settings);

    await _stop(tester, state);
  });
}
