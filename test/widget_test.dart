// Starts the app and checks the Home screen and navigation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/main.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home screen shows the welcome hero and recent projects', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    late AppState state;
    await tester.runAsync(() async {
      state = AppState();
      await state.load();
    });
    await tester.pumpWidget(RoboCoreApp(state: state));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('WELCOME BACK, FREDRICK'), findsOneWidget);
    expect(find.text('RECENT PROJECTS'), findsOneWidget);
    expect(find.text('Blink LED'), findsWidgets);

    await tester.tap(find.text('Examples').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Blink an LED'), findsOneWidget);

    state.sim.stop();
    await tester.pump(const Duration(seconds: 3));
  });
}
