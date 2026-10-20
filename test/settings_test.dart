// Settings: the editor pane sizes the user dragged are kept, and older saved settings still load.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/state/models.dart';

void main() {
  test('pane sizes are saved and loaded', () {
    final s = Settings()
      ..cppPaneWidth = 640
      ..consoleHeight = 300;
    final back = Settings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.cppPaneWidth, 640);
    expect(back.consoleHeight, 300);
  });

  test('settings saved before pane sizes existed get the defaults', () {
    final old = Settings.fromJson({'theme': 'navy', 'fontSize': 14});
    expect(old.theme, 'navy');
    expect(old.cppPaneWidth, Settings.defaultCppPaneWidth);
    expect(old.consoleHeight, Settings.defaultConsoleHeight);
  });
}
