import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:robocore_ide/ui/widgets/cards.dart';

void main() {
  test('code project cards show the first real lines of C++', () {
    final p = Project(
      id: 'x',
      name: 'Test',
      board: 'v2',
      mode: 'code',
      setup: [],
      loop: [],
      files: [ProjectFile('Test.ino', '// My robot\n\n#include <Wire.h>\nvoid setup() {\n}\n')],
      codeEdited: true,
      autosave: true,
      updated: 0,
    );
    expect(CodeThumb.codeLines(p).first, '#include <Wire.h>');
  });
}
