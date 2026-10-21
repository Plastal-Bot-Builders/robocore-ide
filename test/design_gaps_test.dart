// The last design gaps: Help in search (G-11), the Serial Monitor without a board (SM-07), Stop in the top bar
// (E-07) and the preview board's sensors, live and settable (PB-01). Then the small differences from the component review.
import 'package:flutter/material.dart'
    show AnimatedContainer, BoxDecoration, Container, EditableText, FontWeight, SizedBox, Slider, Text, TextSpan, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/data/catalog.dart';
import 'package:robocore_ide/engine/compiler.dart' show Problem;
import 'package:robocore_ide/hw/usb_link.dart';
import 'package:robocore_ide/main.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/state/sim_board.dart';
import 'package:robocore_ide/theme.dart' show kBrand;
import 'package:robocore_ide/ui/shell.dart' show SearchBox, TopBar, kHelpTopics;
import 'package:robocore_ide/ui/widgets/common.dart' show tipped;
import 'package:shared_preferences/shared_preferences.dart';

/// A browser with Web Serial and no board plugged in, until Connect.
class _NoBoardUsb extends UsbLink {
  bool open = false;
  bool pick = false; // false: the student closes the browser's port chooser
  @override
  bool get supported => true;
  @override
  bool get isOpen => open;
  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) async {
    if (!pick) return const UsbResult(false, code: 'cancelled', message: 'No port was chosen.');
    open = true;
    return const UsbResult(true, data: {'label': 'ESP32-S3 USB (303A:1001)'});
  }

  @override
  Future<UsbResult> reconnect({required int baud}) async => const UsbResult(false, code: 'none', message: 'No board plugged in.');
  @override
  Future<UsbResult> disconnect() async {
    open = false;
    return const UsbResult(true);
  }

  @override
  Future<UsbResult> setBaud(int baud) async => const UsbResult(true);
  @override
  Future<UsbResult> write(String text) async => const UsbResult(true);
  @override
  Future<UsbResult> reset({String arch = 'esp32'}) async => const UsbResult(true);
  @override
  Future<UsbResult> flash(Map<String, dynamic> job) async => const UsbResult(false, code: 'none');
  @override
  Future<UsbResult> cancelFlash() async => const UsbResult(true);
  @override
  Future<UsbResult> identify({required int baud, String arch = 'esp32'}) async => const UsbResult(false, code: 'none');
}

Future<AppState> _start(WidgetTester tester, {UsbLink? usb}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1800, 1000));
  late AppState state;
  await tester.runAsync(() async {
    state = AppState(usbLink: usb);
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
  test('help topics match the start of a word', () {
    List<String> find(String q) => [for (final h in kHelpTopics.where((h) => h.matches(q))) h.name];
    expect(find('board'), ['Board Setup']);
    expect(find('test conn'), ['Board Setup']);
    expect(find('keyb'), ['Keyboard shortcuts']);
    expect(find('BAUD'), ['Serial Monitor']);
    expect(find('?'), isEmpty);
  });

  testWidgets('search has a Help group: pages and dialogs by name or by a word (G-11)', (tester) async {
    final state = await _start(tester);
    await tester.enterText(find.descendant(of: find.byType(SearchBox), matching: find.byType(EditableText)), 'baud');
    await tester.pump();
    await tester.pump();
    expect(find.text('HELP'), findsOneWidget);
    expect(find.text('Serial Monitor'), findsWidgets);
    await tester.tap(find.text('Help'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.view, Screen.serial);

    // Enter opens the first result when only Help matches.
    await tester.enterText(find.descendant(of: find.byType(SearchBox), matching: find.byType(EditableText)), 'shortcuts');
    await tester.pump();
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('KEYBOARD SHORTCUTS'), findsOneWidget);
    expect(find.text('Move between blocks'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    await _stop(tester, state);
  });

  testWidgets('the Serial Monitor without a board says so, with Connect (SM-07)', (tester) async {
    final usb = _NoBoardUsb();
    final state = await _start(tester, usb: usb);
    state.setPort(kPortUsb);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    state.go(Screen.serial);
    state.clearLog();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.usbOpen, isFalse);
    expect(find.text('NO BOARD CONNECTED'), findsOneWidget);

    // With earlier lines in the log, a bar above them.
    state.serialPush('Hello from before', 'out');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('NO BOARD CONNECTED'), findsNothing);
    expect(find.textContaining('No board connected.', findRichText: true), findsOneWidget);
    expect(find.textContaining('Hello from before', findRichText: true), findsOneWidget);

    usb.pick = true;
    await tester.tap(find.text('Connect'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.usbOpen, isTrue);
    expect(find.textContaining('No board connected', findRichText: true), findsNothing);

    await _stop(tester, state);
  });

  testWidgets('Stop shows only while something runs: it stops the sketch, or cancels Verify (E-07)', (tester) async {
    final state = await _start(tester);
    state.openProject(state.sortedProjects.firstWhere((p) => p.mode == 'code' && p.board == 'v2').id);
    await tester.pump(const Duration(milliseconds: 100));
    state.rerun();
    if (state.lastRun == null) {
      await state.upload();
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.sim.running, isTrue);
    expect(find.byTooltip('Stop the sketch'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop the sketch'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.sim.running, isFalse);
    expect(find.byTooltip('Stop the sketch'), findsNothing);

    // Verify runs for a moment (the preview check): Stop cancels it.
    state.verify();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.busy, 'verify');
    expect(find.descendant(of: find.byType(TopBar), matching: find.text('Verifying…')), findsOneWidget,
        reason: 'the Verify button shows it is working');
    await tester.tap(find.byTooltip('Cancel Verify'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.busy, isNull);
    expect(state.stateLabel, 'Cancelled');
    await tester.pump(const Duration(seconds: 2));
    expect(state.stateLabel, 'Cancelled', reason: 'the cancelled check does not report afterwards');
    expect(find.byTooltip('Cancel Verify'), findsNothing);

    await _stop(tester, state);
  });

  testWidgets('the preview board shows sonar, line, tilt and battery, and each can be held at a value (PB-01)', (tester) async {
    final state = await _start(tester);
    state.openProject(state.sortedProjects.firstWhere((p) => p.mode == 'code' && p.board == 'v2').id);
    if (!state.panelOpen) state.togglePanel();
    await tester.pump(const Duration(milliseconds: 100));
    // Beside the console on a wide window; in the console's Board tab otherwise.
    if (find.text('Motors').evaluate().isEmpty) {
      await tester.tap(find.text('Board').last);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('PREVIEW BOARD'), findsOneWidget);
    for (final k in ['Motors', 'Servo 1', 'Sonar', 'Line', 'Tilt', 'Battery']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.text('42 cm'), findsOneWidget);

    await tester.ensureVisible(find.text('Sonar'));
    await tester.tap(find.text('Sonar'));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
    await tester.ensureVisible(find.byType(Slider));
    await tester.tapAt(tester.getRect(find.byType(Slider)).centerLeft + const Offset(1, 0));
    await tester.pump();
    final cm = state.sim.held[SimSensor.sonar]!;
    expect(cm, lessThan(10));
    expect(find.text('${cm.round()} cm'), findsOneWidget);
    FontWeight? weight(String t) => tester.widget<Text>(find.text(t)).style?.fontWeight;
    expect(weight('${cm.round()} cm'), FontWeight.w800, reason: 'a held reading is bold');
    expect(state.sim.distance(), cm, reason: 'the sketch reads exactly the held value');

    await tester.ensureVisible(find.text('Auto'));
    await tester.tap(find.text('Auto'));
    await tester.pump();
    expect(state.sim.held, isEmpty);
    expect(weight('${state.sim.reading(SimSensor.sonar).round()} cm'), FontWeight.w400, reason: 'simulated again');

    // Another sensor's slider replaces the open one.
    await tester.ensureVisible(find.text('Line'));
    await tester.tap(find.text('Line'));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
    await tester.ensureVisible(find.byType(Slider));
    await tester.tapAt(tester.getRect(find.byType(Slider)).centerRight - const Offset(1, 0));
    await tester.pump();
    expect(state.sim.held[SimSensor.line], greaterThan(.9));
    expect(find.textContaining('R 1.0'), findsOneWidget);
    state.sim.hold(SimSensor.line, null);

    await _stop(tester, state);
  });

  // The small differences in docs/component-review.md.
  test('a tooltip shows its shortcut faint after the label', () {
    final tip = tipped('Verify (Cmd+R)', const SizedBox()) as Tooltip;
    final spans = (tip.richMessage! as TextSpan).children!;
    expect((spans.first as TextSpan).text, 'Verify');
    expect((spans.last as TextSpan).text, 'Cmd+R');
    expect((spans.last as TextSpan).style!.color!.a, closeTo(.7, .01));
    expect((tipped('Close Cog (Ctrl+I)', const SizedBox()) as Tooltip).richMessage, isNotNull);
    expect((tipped('Board setup', const SizedBox()) as Tooltip).message, 'Board setup', reason: 'no shortcut: plain');
  });

  testWidgets('the Problems tab has a trash button that clears the list', (tester) async {
    final state = await _start(tester);
    state.openProject(state.sortedProjects.firstWhere((p) => p.mode == 'code' && p.board == 'v2').id);
    if (!state.panelOpen) state.togglePanel();
    state.problems = [const Problem('Blink.ino', 2, "'digitalwrite' was not declared in this scope")];
    state.setPanelTab('problems');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Clear problems'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.problems, isEmpty);
    expect(find.text('No problems in this sketch.'), findsOneWidget);

    await _stop(tester, state);
  });

  testWidgets('without a board the board card reads the port as None selected', (tester) async {
    final state = await _start(tester, usb: _NoBoardUsb());
    state.setPort(kPortUsb);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    state.go(Screen.home);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.linked, isFalse);
    expect(find.text('None selected'), findsOneWidget);

    await _stop(tester, state);
  });

  testWidgets('the preview board: USER is outlined until held, and a white LED is lit in the box yellow', (tester) async {
    final state = await _start(tester);
    state.openProject(state.sortedProjects.firstWhere((p) => p.mode == 'code' && p.board == 'v2').id);
    if (!state.panelOpen) state.togglePanel();
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('USER').evaluate().isEmpty) {
      await tester.tap(find.text('Board').last);
      await tester.pump(const Duration(milliseconds: 100));
    }
    BoxDecoration user() => tester
        .widget<AnimatedContainer>(find.ancestor(of: find.text('USER'), matching: find.byType(AnimatedContainer)).first)
        .decoration! as BoxDecoration;
    expect(user().color, isNull, reason: 'outlined when up');
    final press = await tester.startGesture(tester.getCenter(find.text('USER')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.sim.user, isTrue);
    expect(user().color, isNotNull, reason: 'filled while held');
    await press.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(user().color, isNull);

    // The sketch turns the RGB LED white (digitalWrite on LED_BUILTIN).
    state.sim.running = true;
    state.sim.rgbColor = const [255, 255, 255];
    state.sim.setUser(false); // tells the board card
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('RGB · white'), findsOneWidget);
    final yellow = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 44 && // the LED ring
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).color == kBrand);
    expect(yellow, findsOneWidget);

    await _stop(tester, state);
  });
}
