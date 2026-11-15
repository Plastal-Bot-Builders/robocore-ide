import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:robocore_ide/ui/widgets/cards.dart';

Project _p({String mode = 'blocks', String? blockly, String code = ''}) => Project(
      id: 'x',
      name: 'Test',
      board: 'v2',
      mode: mode,
      setup: [
        {'t': 'serial', 'baud': '115200'}
      ],
      loop: [
        {'t': 'tone', 'pin': '46', 'note': 'C4', 'secs': 0.5},
        {'t': 'wait', 'secs': 1},
      ],
      files: [ProjectFile('Test.ino', code)],
      codeEdited: false,
      autosave: true,
      updated: 0,
      blockly: blockly,
    );

void main() {
  group('Project card preview', () {
    test('uses the rows the blocks editor saved', () {
      final json = jsonEncode({
        'blocks': {},
        'rcPreview': [
          [0, 'on start', 'events'],
          [1, 'play note C4 for 0.5 s', 'light'],
        ],
      });
      final rows = ProjectThumb.rows(_p(blockly: json))!;
      expect(rows, [(0, 'on start', 'events'), (1, 'play note C4 for 0.5 s', 'light')]);
    });

    test('builds rows from the old block lists', () {
      final rows = ProjectThumb.rows(_p())!;
      // Only serial set-up in "on start": left out, so the card starts at "forever".
      expect(rows.first, (0, 'forever', 'events'));
      expect(rows.any((r) => r.$2.startsWith('start serial')), isFalse);
      final tone = rows.firstWhere((r) => r.$2.contains('C4'));
      expect(tone.$3, 'light');
      expect(tone.$1, 1);
    });

    test('code projects show their first real lines', () {
      final p = _p(mode: 'code', code: '// My robot\n\n#include <Wire.h>\nvoid setup() {\n}\n');
      expect(ProjectThumb.rows(p), isNull);
      expect(ProjectThumb.codeLines(p).first, '#include <Wire.h>');
    });

    test('blocks saved before previews existed fall back to code', () {
      expect(ProjectThumb.rows(_p(blockly: '{"blocks":{}}')), isNull);
    });
  });
}
