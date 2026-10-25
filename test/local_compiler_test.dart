// Compiling on this Mac reads arduino-cli's output as the compile server does (server/src/parse.js and its
// "parsers" test in server/test/server.test.js), so problems, sizes and errors look the same either way.
import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/hw/local_compiler_native.dart';

void main() {
  test('compiler messages become problems in the sketch’s files, or in a library', () {
    final p = parseDiagnostics([
      "Blink.ino:12:5: error: 'x' was not declared in this scope",
      'Blink.ino:12:5: note: suggested alternative',
      'config.h:2:1: warning: extra tokens',
      '<RoboCore>/src/RoboCoreMotors.cpp:40:3: error: oops',
    ].join('\n'), ['Blink.ino', 'config.h']);
    expect(p.length, 3);
    expect(p[0], {'severity': 'error', 'file': 'Blink.ino', 'line': 12, 'column': 5, 'message': "'x' was not declared in this scope"});
    expect(p[1]['severity'], 'warning');
    expect(p[2]['file'], 'library');
    expect(p[2]['source'], 'src/RoboCoreMotors.cpp');
  });

  test('a missing setup() or loop() is explained', () {
    final p = parseDiagnostics("main.cpp:(.text.main+0x8): undefined reference to `setup'", ['Blink.ino']);
    expect(p.single['file'], 'Blink.ino');
    expect(p.single['message'], contains('Every sketch needs a setup() function.'));
  });

  test('sizes, and the JSON after anything arduino-cli printed first', () {
    expect(
      parseSizes(const {}, 'Sketch uses 10 bytes (1%) of program storage space. Maximum is 100 bytes.\n'
          'Global variables use 5 bytes (1%) of dynamic memory, leaving 1 bytes for local variables. Maximum is 50 bytes.'),
      {
        'flash': {'used': 10, 'max': 100},
        'ram': {'used': 5, 'max': 50},
      },
    );
    expect(
      parseSizes(const {
        'builder_result': {
          'executable_sections_size': [
            {'name': 'text', 'size': 3822, 'max_size': 32256},
            {'name': 'data', 'size': 213, 'max_size': 2048},
          ],
        },
      }, ''),
      {
        'flash': {'used': 3822, 'max': 32256},
        'ram': {'used': 213, 'max': 2048},
      },
    );
    expect(parseCliJson('noise\n{"success":true}'), {'success': true});
    expect(parseCliJson('nothing'), isNull);
  });

  test('structured diagnostics come first, and the text log does not repeat them', () {
    final structured = parseStructured([
      {'severity': 'ERROR', 'file': '/tmp/rc/Blink/Blink.ino', 'line': 3, 'column': 1, 'message': "expected ';' before '}'"},
      {'severity': 'NOTE', 'file': '/tmp/rc/Blink/Blink.ino', 'line': 3, 'message': 'in expansion'},
    ], '/tmp/rc/Blink', ['Blink.ino']);
    final text = parseDiagnostics("Blink.ino:3:1: error: expected ';' before '}'", ['Blink.ino']);
    final all = mergeProblems(structured, text);
    expect(all.single['file'], 'Blink.ino');
    expect(all.single['line'], 3);
  });
}
