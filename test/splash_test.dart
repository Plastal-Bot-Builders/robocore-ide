// The launch animation: it shows while the app loads, waits for the load, then fades into the app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/main.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/ui/splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the splash plays while the app loads, then fades into Welcome', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final state = AppState();
    final ready = Completer<void>();
    await tester.pumpWidget(LaunchApp(state: state, ready: ready.future));

    // Loading: only the splash, and after its intro it waits (the ring rocks, "Loading your projects…").
    expect(find.byType(Splash), findsOneWidget);
    expect(find.byType(RoboCoreApp), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Splash), findsOneWidget);
    expect(find.text('Loading your projects…'), findsOneWidget);

    // Loaded: the app appears under the splash, which fades out and goes.
    await tester.runAsync(state.load);
    ready.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(RoboCoreApp), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Splash), findsNothing);
    expect(find.text('WELCOME TO ROBOCORE'), findsOneWidget);
  });

  testWidgets('a quick load still shows the whole intro, about 1.5 s in all', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final state = AppState();
    await tester.runAsync(state.load);
    await tester.pumpWidget(LaunchApp(state: state, ready: Future.value()));
    var ms = 0;
    while (find.byType(Splash).evaluate().isNotEmpty && ms < 5000) {
      await tester.pump(const Duration(milliseconds: 20));
      ms += 20;
    }
    expect(ms, inInclusiveRange(1400, 1600));
    expect(find.text('WELCOME TO ROBOCORE'), findsOneWidget);
  });
}
