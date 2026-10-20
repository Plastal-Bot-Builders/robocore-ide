// Projects: unique names, rename, duplicate, delete, the filtered list, Reset all data, toasts, and the
// .zip a sketch with several tabs downloads as.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/engine/zip.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _state() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState();
  await s.load();
  s.sim.stop();
  s.setProfile(name: 'Thandi Mokoena', school: 'Grade 7B');
  return s;
}

Project _named(AppState s, String name) => s.projects.firstWhere((p) => p.name == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('project names are required, plain and unique (except the project being renamed)', () async {
    final s = await _state();
    final blink = _named(s, 'Blink LED');
    expect(s.validateName(''), isNotNull);
    expect(s.validateName('Blink!'), isNotNull);
    expect(s.validateName('blink led'), contains('already have a project'));
    expect(s.validateName('Blink LED', except: blink), isNull);
    expect(s.validateName('Robot dance'), isNull);
  });

  test('rename and duplicate', () async {
    final s = await _state();
    final blink = _named(s, 'Blink LED');
    s.duplicateProject(blink);
    s.duplicateProject(blink);
    expect(s.sortedProjects.first.name, 'Blink LED copy 2', reason: 'the newest copy is at the top');
    expect(s.projects.where((p) => p.name.startsWith('Blink LED copy')), hasLength(2));
    final copy = _named(s, 'Blink LED copy');
    expect(copy.id, isNot(blink.id));
    expect(copy.files.first.content, blink.files.first.content);
    expect(s.toast, contains('“Blink LED copy 2” is in Projects'));

    s.renameProject(copy, '  Disco lights ');
    expect(copy.name, 'Disco lights');
    expect(s.toast, 'Renamed to “Disco lights”.');
  });

  test('deleting another project keeps the open one open', () async {
    final s = await _state();
    final blink = _named(s, 'Blink LED');
    s.openProject(blink.id);
    s.deleteProject(_named(s, 'Distance monitor'));
    expect(s.cur, same(blink));
    expect(s.view, Screen.editor);
    s.deleteProject(blink);
    expect(s.cur, isNull);
    expect(s.view, Screen.projects);
  });

  test('the Projects list follows the chips and the filter', () async {
    final s = await _state();
    s.setFilter(ptab: 'code');
    expect(s.filteredProjects.every((p) => p.mode == 'code'), isTrue);
    s.setFilter(ptab: 'all', pfilter: 'blink');
    expect(s.filteredProjects.map((p) => p.name), ['Blink LED']);
  });

  test('Reset all data: projects, profile and settings go; a new profile gets the starter projects', () async {
    final s = await _state();
    s.updateSettings((x) => x.fontSize = 18);
    s.toggleSidebar();
    await s.resetAll();
    expect(s.needsProfile, isTrue);
    expect(s.projects, isEmpty);
    expect(s.settings.fontSize, 13);
    expect(s.sideCollapsed, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('robocore-ide-v1'), isNull);
    s.setProfile(name: 'Mwila');
    expect(s.projects, hasLength(5));
  });

  test('success toasts hide after 4 s; errors stay until closed', () async {
    final s = await _state();
    s.showToast('Saved.');
    await Future<void>.delayed(const Duration(milliseconds: 4100));
    expect(s.toast, isNull);
    s.showToast('The board was unplugged.', error: true);
    await Future<void>.delayed(const Duration(milliseconds: 4100));
    expect(s.toast, 'The board was unplugged.');
    s.closeToast();
    expect(s.toast, isNull);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('the explanation level is saved and defaults to Beginner', () {
    expect(Settings().cogLevel, 'beginner');
    expect(Settings.fromJson({'cogLevel': 'advanced'}).cogLevel, 'advanced');
    expect(Settings.fromJson({'cogLevel': 'wizard'}).cogLevel, 'beginner');
    expect((Settings()..cogLevel = 'intermediate').toJson()['cogLevel'], 'intermediate');
  });

  group('zip', () {
    int u16(Uint8List b, int o) => b[o] | b[o + 1] << 8;
    int u32(Uint8List b, int o) => u16(b, o) | u16(b, o + 2) << 16;

    test('crc32 matches the standard check value', () {
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    });

    test('a sketch folder with its tabs, readable from the central directory', () {
      final z = zipFiles({'Blink/Blink.ino': 'void setup() {}\n', 'Blink/motors.h': '// ✓ utf-8\n'}, time: DateTime(2026, 10, 20, 9, 30));
      expect(u32(z, 0), 0x04034b50);
      final end = z.length - 22;
      expect(u32(z, end), 0x06054b50);
      expect(u16(z, end + 10), 2, reason: 'two entries');
      var o = u32(z, end + 16);
      final names = <String>[];
      for (var i = 0; i < 2; i++) {
        expect(u32(z, o), 0x02014b50);
        final n = u16(z, o + 28);
        final local = u32(z, o + 42);
        final name = utf8.decode(z.sublist(o + 46, o + 46 + n));
        names.add(name);
        // The local header's data is the file, and its CRC is right.
        final size = u32(z, local + 18);
        final data = z.sublist(local + 30 + u16(z, local + 26), local + 30 + u16(z, local + 26) + size);
        expect(crc32(data), u32(z, local + 14));
        o += 46 + n;
      }
      expect(names, ['Blink/Blink.ino', 'Blink/motors.h']);
    });
  });
}
