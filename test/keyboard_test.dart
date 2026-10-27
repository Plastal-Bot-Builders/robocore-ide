// Keyboard access (WCAG 2.1.1, 2.4.7): every button built on Hover takes the focus with Tab, shows a ring and is pressed
// with Enter or Space; menus move with the arrow keys and give the focus back when Esc closes them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/theme.dart';
import 'package:robocore_ide/ui/widgets/common.dart';
import 'package:robocore_ide/ui/widgets/menu.dart';

Widget _app(Widget child) => MaterialApp(theme: buildTheme(RC.paper), home: Scaffold(body: Center(child: child)));

/// The ring Hover draws around a focused control.
Finder _ring(Color color) => find.byWidgetPredicate((w) =>
    w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border == Border.all(color: color, width: 2));

void main() {
  testWidgets('Tab reaches a button, Enter and Space press it, and a ring shows where the focus is', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_app(Row(mainAxisSize: MainAxisSize.min, children: [
      Btn('Save', onTap: () => pressed++),
      const Btn('Off'), // disabled: skipped by Tab
    ])));
    expect(_ring(RC.paper.focus), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_ring(RC.paper.focus), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(pressed, 2);
  });

  testWidgets('a switch toggles from the keyboard', (tester) async {
    var on = false;
    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, set) => RcSwitch(value: on, label: 'Autocomplete', onChanged: (v) => set(() => on = v)),
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(on, isTrue);
  });

  testWidgets('on the yellow top bar the ring is navy whatever the theme', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(RC.navy),
      home: Scaffold(body: Center(child: FocusRing(color: kNavy, child: IconBtn('menu', onTap: () {}, tip: 'Open menu')))),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_ring(kNavy), findsOneWidget);
    expect(_ring(RC.navy.focus), findsNothing);
  });

  testWidgets('menus: arrow keys move between the rows, Enter picks one, Esc gives the focus back', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(_app(MenuButton(
      entries: () => [
        MenuEntry('Open', onTap: () => picked.add('Open')),
        MenuEntry.line,
        MenuEntry('Rename…', onTap: () => picked.add('Rename')),
        MenuEntry('Delete…', onTap: () => picked.add('Delete')),
      ],
      builder: (context, open, toggle) => Btn('Project', onTap: toggle),
    )));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // the Project button
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Rename…'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // Open
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // Rename… (the divider is skipped)
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['Rename']);
    expect(find.text('Rename…'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // the focus is back on the Project button: the menu opens again
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // from nothing up wraps to the last row
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(picked, ['Rename', 'Delete']);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget, reason: 'Esc left the focus on the button that opened the menu');
  });
}
