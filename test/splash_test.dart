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
    await tester.pump(const Duration(milliseconds: 3800));
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

  testWidgets('a quick load still shows the whole animation, about 4 s in all', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final state = AppState();
    await tester.runAsync(state.load);
    await tester.pumpWidget(LaunchApp(state: state, ready: Future.value()));
    var ms = 0;
    while (find.byType(Splash).evaluate().isNotEmpty && ms < 8000) {
      await tester.pump(const Duration(milliseconds: 20));
      ms += 20;
    }
    expect(ms, inInclusiveRange(3900, 4100));
    expect(find.text('WELCOME TO ROBOCORE'), findsOneWidget);
  });

  // The Mac app opens with MacIntro instead (the gear ring spins round the planet), on the same terms.
  double captionOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find.ancestor(of: find.text('Opening your projects…'), matching: find.byType(Opacity)).first)
      .opacity;

  testWidgets('the Mac intro spins, waits for the projects, then fades into the app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    var done = false;
    Widget intro(bool ready) => Directionality(
          textDirection: TextDirection.ltr,
          child: MacIntro(key: const ValueKey('intro'), state: state, ready: ready, onDone: () => done = true),
        );
    await tester.pumpWidget(intro(false));

    // Still loading after the spin: the icon stays, and says so.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(done, isFalse);
    expect(captionOpacity(tester), 1);

    // Loaded: the caption goes and the intro fades out.
    await tester.pumpWidget(intro(true));
    expect(captionOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(done, isTrue);
  });

  testWidgets('a quick load: the Mac intro leaves as soon as the ring has settled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var done = false;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MacIntro(state: AppState(), ready: true, onDone: () => done = true),
    ));
    expect(captionOpacity(tester), 0);
    var ms = 0;
    while (!done && ms < 4000) {
      await tester.pump(const Duration(milliseconds: 20));
      ms += 20;
    }
    expect(ms, inInclusiveRange(1700, 1900));
  });
}
