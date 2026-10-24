// The macOS app's projects folder: projects as sketch folders on disk (FolderStore, in a temporary folder), and the
// app moving its projects there, coping with a missing folder, and never deleting files except to the Trash.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/data/catalog.dart';
import 'package:robocore_ide/hw/sketchbook_native.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:robocore_ide/state/project_folder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state_test.dart' show FakeUsb;

/// A projects folder in memory, recording what the app asks of it.
class FakeFolder implements ProjectFolder {
  FakeFolder([List<Project>? inside]) : inside = [...?inside];
  List<Project> inside;
  final removed = <String>[];
  var forgotten = false;

  @override
  String get path => '/Users/test/Documents/RoboCore';
  @override
  Future<List<Project>> readAll({required String defaultBoard}) async => [for (final p in inside) p.copy()];
  @override
  void write(List<Project> projects) => inside = [for (final p in projects) p.copy()];
  @override
  Future<void> remove(Project p) async => removed.add(p.name);
  @override
  Future<void> reveal([Project? p]) async {}
  @override
  Future<void> forget() async => forgotten = true;
}

String _saved(List<Project> projects, {String? folder}) => jsonEncode({
      'v': 1,
      'profile': true,
      'user': 'Fredrick',
      'board': 'uno',
      'projects': [for (final p in projects) p.toJson()],
      if (folder != null) 'folder': folder,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FolderStore', () {
    late Directory tmp;
    late FolderStore store;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('rc-projects-');
      store = FolderStore(tmp.path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a project is a sketch folder named after its main file, and reads back the same', () async {
      final p = projectFrom(exampleById('traffic'), name: 'Traffic light', board: 'uno');
      store.write([p]);
      await store.flush();
      final dir = Directory('${tmp.path}/${sketchFolderName(p.files.first.name)}');
      expect(File('${dir.path}/${p.files.first.name}').readAsStringSync(), p.files.first.content);
      expect(File('${dir.path}/config.h').existsSync(), isTrue);
      expect(File('${dir.path}/$kProjectMetaFile').existsSync(), isTrue);

      final back = (await FolderStore(tmp.path).readAll(defaultBoard: 'v2')).single;
      expect(back.toJson(), p.toJson());
    });

    test('only changes are written; a renamed main file renames the folder; a closed tab removes its file', () async {
      final p = projectFrom(exampleById('blink'), name: 'Blink LED', board: 'uno');
      store.write([p]);
      await store.flush();
      final first = Directory('${tmp.path}/Blink');
      expect(first.existsSync(), isTrue);

      p.files.first.name = 'MyBlink.ino';
      p.files.removeWhere((f) => f.name == 'config.h');
      store.write([p]);
      await store.flush();
      expect(first.existsSync(), isFalse);
      final moved = Directory('${tmp.path}/MyBlink');
      expect(File('${moved.path}/MyBlink.ino').existsSync(), isTrue);
      expect(File('${moved.path}/config.h').existsSync(), isFalse);
      expect(File('${moved.path}/Blink.ino').existsSync(), isFalse);
    });

    test('Arduino sketches already there become code projects; other folders are left alone', () async {
      Directory('${tmp.path}/Fade').createSync();
      File('${tmp.path}/Fade/Fade.ino').writeAsStringSync('void setup() {}\nvoid loop() {}\n');
      File('${tmp.path}/Fade/pins.h').writeAsStringSync('#pragma once\n');
      Directory('${tmp.path}/Photos').createSync();
      File('${tmp.path}/Photos/robot.jpg').writeAsStringSync('not a sketch');
      Directory('${tmp.path}/.hidden').createSync();

      final all = await store.readAll(defaultBoard: 'uno');
      expect(all.map((p) => p.name), ['Fade']);
      final fade = all.single;
      expect(fade.mode, 'code');
      expect(fade.board, 'uno');
      expect(fade.files.map((f) => f.name), ['Fade.ino', 'pins.h']);
      expect(File('${tmp.path}/Photos/robot.jpg').existsSync(), isTrue);
    });

    test('files added in Finder join the project; a folder copied in Finder becomes a project of its own', () async {
      final p = projectFrom(exampleById('blink'), name: 'Blink LED', board: 'uno');
      store.write([p]);
      await store.flush();
      File('${tmp.path}/Blink/extra.h').writeAsStringSync('// extra\n');
      Process.runSync('cp', ['-R', '${tmp.path}/Blink', '${tmp.path}/Blink copy']);

      final all = await FolderStore(tmp.path).readAll(defaultBoard: 'uno');
      expect(all.length, 2);
      expect(all.first.files.map((f) => f.name), ['Blink.ino', 'config.h', 'extra.h']);
      expect(all.map((p) => p.id).toSet().length, 2, reason: 'the copy got its own id');
    });

    test('a new project never writes into a folder that is already there', () async {
      Directory('${tmp.path}/Blink').createSync();
      File('${tmp.path}/Blink/notes.txt').writeAsStringSync('mine');
      final p = projectFrom(exampleById('blink'), name: 'Blink LED', board: 'uno');
      store.write([p]);
      await store.flush();
      expect(File('${tmp.path}/Blink/notes.txt').readAsStringSync(), 'mine');
      expect(File('${tmp.path}/Blink_2/Blink.ino').existsSync(), isTrue);
    });
  });

  group('The app with a projects folder', () {
    Future<AppState> start({required String saved, ProjectFolder? folder}) async {
      SharedPreferences.setMockInitialValues({'robocore-ide-v1': saved});
      final s = AppState(usbLink: FakeUsb())
        ..chooseFolder = (() async => FakeFolder())
        ..folder = folder;
      await s.load();
      return s;
    }

    test('the projects saved in the app move into the folder, and a copy of them is kept aside', () async {
      final blink = projectFrom(exampleById('blink'), name: 'Blink LED', board: 'uno');
      final folder = FakeFolder();
      final s = await start(saved: _saved([blink]), folder: folder);
      expect(s.projects.map((p) => p.name), ['Blink LED']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(folder.inside.map((p) => p.name), ['Blink LED']);
      final prefs = await SharedPreferences.getInstance();
      final now = jsonDecode(prefs.getString('robocore-ide-v1')!) as Map;
      expect(now['projects'], isEmpty);
      expect(now['folder'], folder.path);
      expect(prefs.getKeys().any((k) => k.startsWith('robocore-ide-v1-before-folder')), isTrue);
    });

    test('a folder that can’t be opened is reported, and the samples are not put back', () async {
      final s = await start(saved: _saved([], folder: '/Volumes/USB/RoboCore'));
      expect(s.missingFolder, '/Volumes/USB/RoboCore');
      expect(s.loadNotice, contains('/Volumes/USB/RoboCore'));
      expect(s.projects, isEmpty);
      expect(s.shouldAskFolder, isFalse);
    });

    test('deleting a project sends its folder to the Trash; Reset all data leaves the files alone', () async {
      final a = projectFrom(exampleById('blink'), name: 'Blink LED', board: 'uno');
      final b = projectFrom(exampleById('traffic'), name: 'Traffic light', board: 'uno');
      final folder = FakeFolder([a, b]);
      final s = await start(saved: _saved([]), folder: folder);
      s.deleteProject(s.projects.firstWhere((p) => p.name == 'Traffic light'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(folder.removed, ['Traffic light']);
      await s.resetAll();
      expect(folder.forgotten, isTrue);
      expect(folder.removed, ['Traffic light'], reason: 'nothing else went to the Trash');
      expect(s.folder, isNull);
    });

    test('copies of one example get main files of their own (each is a folder named after it)', () async {
      final s = await start(saved: _saved([]), folder: FakeFolder());
      s.openExample('blink');
      s.openExample('blink');
      final mains = s.projects.map((p) => p.files.first.name.toLowerCase()).toList();
      expect(mains.toSet().length, mains.length);
    });

    test('Open Sketch… brings an Arduino sketch in as a code project', () async {
      final s = await start(saved: _saved([]), folder: FakeFolder());
      s.importSketch('Fade', {'Fade.ino': 'void setup() {}\nvoid loop() {}\n', 'pins.h': '#pragma once\n'});
      expect(s.cur!.name, 'Fade');
      expect(s.cur!.mode, 'code');
      expect(s.cur!.files.map((f) => f.name), ['Fade.ino', 'pins.h']);
    });
  });
}
