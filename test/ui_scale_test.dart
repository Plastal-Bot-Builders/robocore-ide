// The display size (lib/ui/widgets/ui_scale.dart): Auto from the screen, the sizes Settings and the View menu step
// through, and the app laid out for a smaller screen and drawn bigger.
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:robocore_ide/ui/widgets/ui_scale.dart';

void main() {
  Future<double> auto(WidgetTester tester, Size screen) async {
    tester.view.display.devicePixelRatio = 2;
    tester.view.display.size = screen * 2;
    late double s;
    await tester.pumpWidget(Builder(builder: (context) {
      s = autoUiScale(context);
      return const SizedBox();
    }));
    return s;
  }

  testWidgets('Auto: 100 % on a 13 or 14 inch MacBook, bigger on a bigger screen, never over 150 %', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(tester.view.display.reset);
    expect(await auto(tester, const Size(1440, 900)), 1.0); // 13 inch
    expect(await auto(tester, const Size(1512, 982)), 1.0); // 14 inch
    expect(await auto(tester, const Size(1728, 1117)), 1.2); // 16 inch
    expect(await auto(tester, const Size(1920, 1080)), 1.2); // a 1080p display: its height decides
    expect(await auto(tester, const Size(3008, 1692)), 1.5); // a 27 inch display
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await auto(tester, const Size(1728, 1117)), 1.0, reason: 'a tablet keeps the design size');
    debugDefaultTargetPlatformOverride = null;
  });

  test('the View menu steps through the sizes, from Auto too', () {
    expect(stepUiScale(1.0, 1), 1.1);
    expect(stepUiScale(1.2, 1), 1.25, reason: 'Auto picked 120 %');
    expect(stepUiScale(1.2, -1), 1.1);
    expect(stepUiScale(1.5, 1), 1.5);
    expect(stepUiScale(0.9, -1), 0.9);
  });

  testWidgets('at 125 % the app is laid out for a screen 1.25 times smaller and drawn 1.25 times bigger', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2500, 1500);
    addTearDown(tester.view.reset);
    late Size seen;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => UiScale(setting: 1.25, child: child!),
      home: Builder(builder: (context) {
        seen = MediaQuery.sizeOf(context);
        return const Align(alignment: Alignment.topLeft, child: SizedBox(key: Key('box'), width: 100, height: 40));
      }),
    ));
    expect(seen, const Size(1000, 600));
    expect(tester.getSize(find.byKey(const Key('box'))), const Size(100, 40), reason: 'its own size, laid out');
    final drawn = tester.getRect(find.byKey(const Key('box')));
    expect(drawn.size, const Size(125, 50), reason: 'on screen');
  });

  test('the display size is saved; Auto by default', () {
    expect(Settings().uiScale, 0);
    expect(Settings.fromJson((Settings()..uiScale = 1.25).toJson()).uiScale, 1.25);
    expect(Settings.fromJson({}).uiScale, 0);
  });
}
