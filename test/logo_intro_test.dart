// The Mac app's opening animation (lib/ui/widgets/logo_intro.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/ui/widgets/logo_intro.dart';

Widget _app(Widget child, {bool still = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Scaffold(body: child),
      ),
    );

void main() {
  test('the ring spins down and settles on the still icon', () {
    expect(LogoIntro.spinAt(Duration.zero), LogoIntro.spinDegrees);
    expect(LogoIntro.spinAt(LogoIntro.spinTime), 0);
    expect(LogoIntro.spinAt(LogoIntro.duration), 0);
    // always slowing down
    var last = LogoIntro.spinDegrees, step = double.infinity;
    for (var ms = 50; ms <= LogoIntro.spinTime.inMilliseconds; ms += 50) {
      final now = LogoIntro.spinAt(Duration(milliseconds: ms));
      expect(now, lessThan(last));
      expect(last - now, lessThanOrEqualTo(step + 1e-9));
      step = last - now;
      last = now;
    }
  });

  testWidgets('plays once, then calls onDone', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(LogoIntro(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 700));
    expect(done, 0);
    await tester.pump(LogoIntro.duration);
    expect(done, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(done, 1);
  });

  testWidgets('shows the caption only once the ring has settled', (tester) async {
    await tester.pumpWidget(_app(const LogoIntro(caption: Text('Opening your projects…'))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
  });

  testWidgets('a click skips it', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(LogoIntro(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(LogoIntro));
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('a key skips it', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(LogoIntro(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('with Reduce motion the icon is still and the app is not held up', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(LogoIntro(onDone: () => done++), still: true));
    await tester.pump();
    expect(done, 1);
  });
}
