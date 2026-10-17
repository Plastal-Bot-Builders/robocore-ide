// Starts the app: the welcome screen asks for a name, then Home greets that person.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/main.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first start asks for a name, then Home greets that user', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    late AppState state;
    await tester.runAsync(() async {
      state = AppState();
      await state.load();
    });
    await tester.pumpWidget(RoboCoreApp(state: state));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('WELCOME TO ROBOCORE'), findsOneWidget);
    expect(find.textContaining('FREDRICK'), findsNothing);

    // An empty name is refused.
    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(find.text('Type your name.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Thandi Mokoena');
    await tester.enterText(find.byType(TextField).last, 'Grade 7B');
    await tester.tap(find.text('Get started'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('WELCOME BACK, THANDI'), findsOneWidget);
    expect(find.text('TM'), findsOneWidget);
    expect(find.text('RECENT PROJECTS'), findsOneWidget);
    expect(find.text('Blink LED'), findsWidgets);
    expect(state.school, 'Grade 7B');

    await tester.tap(find.text('Examples').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Blink an LED'), findsOneWidget);

    state.sim.stop();
    await tester.pump(const Duration(seconds: 3));
  });
}
