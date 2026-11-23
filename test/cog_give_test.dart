// Cog hands blocks and code over: when a reply may (the help style), what goes to the editors, and what the
// panel draws (a stack of blocks, Add to my blocks / Insert in my code / Copy).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/engine/block_script.dart';
import 'package:robocore_ide/engine/compiler.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/state/cog.dart';
import 'package:robocore_ide/ui/app_scope.dart';
import 'package:robocore_ide/ui/cog/cog_panel.dart';
import 'package:robocore_ide/ui/editor/block_picture.dart';

import 'cog_test.dart' show FakeCog, openProject;

const _square = 'To drive in a square, repeat this four times:\n\n'
    '```blocks\n'
    'repeat 4 times\n'
    '  move forward for 10 cm\n'
    '  turn right for 90 °\n'
    '```\n'
    'Put it inside forever.';

Future<void> _show(WidgetTester tester, AppState s, Widget child) => tester.pumpWidget(MaterialApp(
      home: AppScope(notifier: s, child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 340, child: child)))),
    ));

void main() {
  late AppState s;
  late FakeCog fake;
  final blocks = <String>[], code = <String>[];

  setUp(() async {
    (s, fake) = await openProject();
    blocks.clear();
    code.clear();
    cogAddBlocks = blocks.add;
    cogInsertCode = code.add;
  });
  tearDown(() {
    cogAddBlocks = null;
    cogInsertCode = null;
    s.sim.stop();
  });

  group('when Cog may hand blocks or code over', () {
    test('not in Hints first; in Explain the answer and Write code for me', () async {
      for (final (style, give) in [('hints', false), ('explain', true), ('write', true)]) {
        s.updateSettings((x) => x.cogStyle = style);
        await s.cog.ask('How do I blink the LED?');
        expect(s.cog.items.last.kind, CogKind.cog);
        expect(s.cog.items.last.give, give, reason: style);
      }
    });

    test('in the blocks, Show the fix asks for a stack and leaves the project in blocks', () async {
      s.setMode('blocks');
      s.updateSettings((x) => x.cogStyle = 'hints');
      await s.cog.explainError(const Problem('Blink.ino', 2, 'something is wrong'));
      expect(s.cog.canShowFix, isFalse, reason: 'Hints first: two hints come before the fix');
      await s.cog.nextHint();
      await s.cog.nextHint();
      expect(s.cog.canShowFix, isTrue);
      fake.reply = 'The wait was missing.\n```blocks\nwait 1 secs\n```';
      await s.cog.showFix();
      expect(fake.asked.last['task'], 'fix_blocks');
      expect(s.cog.items.last.give, isTrue, reason: 'the student asked for the fix');
      expect(s.cur!.mode, 'blocks');
      expect(s.cog.fixShown, isTrue);
    });
  });

  group('into the project', () {
    test('blocks go to the block editor as stacks, only in a blocks project', () {
      final script = parseBlockScript('repeat 4 times\n  move forward for 10 cm\n  turn right for 90 °');
      expect(s.cur!.mode, 'code');
      expect(s.cog.canAddBlocks, isFalse);
      s.cog.addBlocks(script);
      expect(blocks, isEmpty);

      s.setMode('blocks');
      expect(s.cog.canAddBlocks, isTrue);
      s.cog.addBlocks(script);
      final sent = jsonDecode(blocks.single) as List;
      expect(sent.single['type'], 'controls_repeat_ext');
      expect(sent.single['inputs']['DO']['block']['next']['block']['type'], 'rc_turn');
      expect(s.toast, 'Blocks added beside your program');
      expect(s.toastBody, contains('Drag them into place'));

      s.cog.addBlocks(parseBlockScript('fly to the moon'));
      expect(blocks, hasLength(1), reason: 'nothing to add');
      s.cog.addBlocks(parseBlockScript('stop moving\nfly to the moon'));
      expect(blocks, hasLength(2));
      expect(s.toastBody, contains('1 line is not a block'));
    });

    test('code goes to the cursor, only in a code project', () {
      expect(s.cog.canInsertCode, isTrue);
      s.cog.insertCode('delay(500);');
      expect(code, ['delay(500);']);
      expect(s.toast, 'Code put in at the cursor');
      s.cog.insertCode('   ');
      expect(code, hasLength(1));
      s.setMode('blocks');
      expect(s.cog.canInsertCode, isFalse);
      s.cog.insertCode('delay(1);');
      expect(code, hasLength(1));
    });

    test('an app whose editors take nothing offers neither', () {
      cogAddBlocks = null;
      cogInsertCode = null;
      expect(s.cog.canInsertCode, isFalse);
      s.setMode('blocks');
      expect(s.cog.canAddBlocks, isFalse);
    });

    test('a script may use the project\'s variables', () {
      expect(s.cog.blocksOf('move forward for steps cm').unknown, 1);
      s.cur!.blockly = jsonEncode({
        'variables': [
          {'name': 'steps', 'id': 'v1'}
        ]
      });
      expect(s.cog.blocksOf('move forward for steps cm').unknown, 0);
    });
  });

  group('in the panel', () {
    testWidgets('a blocks script is drawn as a stack, with Add to my blocks and Copy', (tester) async {
      s.setMode('blocks');
      final item = CogItem(CogKind.cog, text: _square, give: true);
      await _show(tester, s, CogText(item.text, item: item));
      expect(find.text('repeat 4 times'), findsOneWidget);
      expect(find.text('move forward for 10 cm'), findsOneWidget);
      expect(find.text('turn right for 90 °'), findsOneWidget);
      expect(find.textContaining('```'), findsNothing);
      expect(find.text('Put it inside forever.'), findsOneWidget);
      // The blocks inside sit further right than the block around them.
      expect(tester.getTopLeft(find.text('move forward for 10 cm')).dx, greaterThan(tester.getTopLeft(find.text('repeat 4 times')).dx));
      // Each bar has its category's colour.
      Color? bar(String text) =>
          (tester.widget<Container>(find.ancestor(of: find.text(text), matching: find.byType(Container)).first).decoration as BoxDecoration).color;
      expect(bar('repeat 4 times'), kBlockColours['control']);
      expect(bar('move forward for 10 cm'), kBlockColours['movement']);

      await tester.tap(find.text('Add to my blocks'));
      expect((jsonDecode(blocks.single) as List).single['type'], 'controls_repeat_ext');
      expect(find.text('Copy'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // the toast's timer
    });

    testWidgets('Hints first shows the stack but does not hand it over', (tester) async {
      s.setMode('blocks');
      final item = CogItem(CogKind.cog, text: _square);
      await _show(tester, s, CogText(item.text, item: item));
      expect(find.text('repeat 4 times'), findsOneWidget);
      expect(find.text('Add to my blocks'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // the project's save timer
    });

    testWidgets('no buttons while the script is still arriving', (tester) async {
      s.setMode('blocks');
      final item = CogItem(CogKind.cog, text: 'Try this:\n```blocks\nrepeat 4 times\n  move forw', give: true, streaming: true);
      await _show(tester, s, CogText(item.text, item: item));
      expect(find.text('repeat 4 times'), findsOneWidget);
      expect(find.text('Add to my blocks'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    group('drawn by the editor\'s own Blockly', () {
      // A 1 × 1 PNG: the widget's size comes from the picture's own width and height.
      final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
      tearDown(() => cogPictureBlocks = null);

      testWidgets('the stack is the editor\'s picture of the blocks, with the same buttons, drawn once', (tester) async {
        s.setMode('blocks');
        final asked = <String>[];
        cogPictureBlocks = (json, ratio) async {
          asked.add(json);
          return BlockPicture(png, 200, 120, ratio);
        };
        final item = CogItem(CogKind.cog, text: _square, give: true);
        await _show(tester, s, CogText(item.text, item: item));
        await tester.pump();
        expect(find.byType(Image), findsOneWidget);
        expect(tester.getSize(find.byType(Image)), const Size(200, 120));
        expect(find.text('repeat 4 times'), findsNothing, reason: 'the picture, not the stack drawn here');
        expect(find.bySemanticsLabel(RegExp('^Blocks: repeat 4 times')), findsOneWidget);
        expect((jsonDecode(asked.single) as List).single['type'], 'controls_repeat_ext');
        expect(find.text('Add to my blocks'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        await _show(tester, s, CogText(item.text, item: item));
        await tester.pump();
        expect(asked, hasLength(1), reason: 'a rebuild shows the same picture');
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('a stack wider than the panel is made at most a quarter smaller, then scrolls sideways', (tester) async {
        s.setMode('blocks');
        cogPictureBlocks = (json, ratio) async => BlockPicture(png, 1000, 100, ratio);
        final item = CogItem(CogKind.cog, text: _square, give: true);
        await _show(tester, s, CogText(item.text, item: item));
        await tester.pump();
        expect(tester.getSize(find.byType(Image)), const Size(750, 75));
        expect(find.ancestor(of: find.byType(Image), matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal)),
            findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('drawn here when the editor can\'t draw it', (tester) async {
        s.setMode('blocks');
        cogPictureBlocks = (json, ratio) async => null;
        final item = CogItem(CogKind.cog, text: _square, give: true);
        await _show(tester, s, CogText(item.text, item: item));
        await tester.pump();
        expect(find.byType(Image), findsNothing);
        expect(find.text('repeat 4 times'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('a line that is not a block is listed under the picture', (tester) async {
        s.setMode('blocks');
        cogPictureBlocks = (json, ratio) async => BlockPicture(png, 120, 40, ratio);
        final item = CogItem(CogKind.cog, text: '```blocks\nstop moving\nfly to the moon\n```', give: true);
        await _show(tester, s, CogText(item.text, item: item));
        await tester.pump();
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('fly to the moon  (not a block)'), findsOneWidget);
        expect(find.textContaining('1 line is not a block'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      });
    });

    test('a picture comes only from a PNG with a size', () {
      const url = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
      final p = BlockPicture.fromPage(url, 683, 1061, 2)!;
      expect((p.width, p.height, p.ratio), (683.0, 1061.0, 2.0));
      expect(p.png.sublist(1, 4), 'PNG'.codeUnits);
      expect(BlockPicture.fromPage(null, 10, 10, 2), isNull);
      expect(BlockPicture.fromPage('data:image/svg+xml;base64,AAAA', 10, 10, 2), isNull);
      expect(BlockPicture.fromPage(url, 0, 10, 2), isNull);
      expect(BlockPicture.fromPage('data:image/png;base64,***', 10, 10, 2), isNull);
    });

    testWidgets('a line that is not a block is said so and stays out', (tester) async {
      s.setMode('blocks');
      final item = CogItem(CogKind.cog, text: '```blocks\nstop moving\nfly to the moon\n```', give: true);
      await _show(tester, s, CogText(item.text, item: item));
      expect(find.text('fly to the moon  (not a block)'), findsOneWidget);
      expect(find.textContaining('1 line is not a block'), findsOneWidget);
      await tester.tap(find.text('Add to my blocks'));
      expect(jsonDecode(blocks.single), [
        {'type': 'rc_stop_moving'}
      ]);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('code gets Insert in my code and Copy in a code project', (tester) async {
      final item = CogItem(CogKind.cog, text: 'Add a pause:\n```cpp\ndelay(500);\n```', give: true);
      await _show(tester, s, CogText(item.text, item: item));
      expect(find.text('delay(500);'), findsOneWidget);
      await tester.tap(find.text('Insert in my code'));
      expect(code, ['delay(500);']);
      await tester.pump(const Duration(seconds: 5));

      // In a blocks project the code can be copied, not inserted; and Hints first never inserts.
      s.setMode('blocks');
      await tester.pump();
      expect(find.text('Insert in my code'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      s.setMode('code');
      final hint = CogItem(CogKind.cog, text: item.text);
      await _show(tester, s, CogText(hint.text, item: hint));
      expect(find.text('Insert in my code'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Cog\'s words without their reply (the quick check, the fix card) have no buttons', (tester) async {
      await _show(tester, s, const CogText('```cpp\ndelay(500);\n```'));
      expect(find.text('delay(500);'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });
  });
}
