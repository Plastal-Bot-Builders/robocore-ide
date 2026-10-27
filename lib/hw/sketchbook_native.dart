// The macOS app's projects folder: the folder itself comes from macos/Runner/Sketchbook.swift (the user picks it,
// a bookmark keeps the permission); the project files are read and written here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/models.dart';
import '../state/project_folder.dart';

const _channel = MethodChannel('robocore/sketchbook');

bool get projectsFolderSupported => defaultTargetPlatform == TargetPlatform.macOS;

/// The folder the user chose before, or null (none yet, or it can't be found).
Future<ProjectFolder?> restoreProjectsFolder() async {
  if (!projectsFolderSupported) return null;
  try {
    final path = await _channel.invokeMethod<String>('restore');
    return path == null ? null : FolderStore(path);
  } catch (_) {
    return null;
  }
}

/// The projects folder at [path] (saved in the settings), when it is there: found by its path when the bookmark
/// can't find it.
ProjectFolder? projectsFolderAt(String path) =>
    projectsFolderSupported && Directory(path).existsSync() ? FolderStore(path) : null;

/// Asks the user where to keep the projects; null when they cancel.
Future<ProjectFolder?> chooseProjectsFolder() async {
  if (!projectsFolderSupported) return null;
  final path = await _channel.invokeMethod<String>('choose');
  return path == null ? null : FolderStore(path);
}

/// File > Open Sketch…: an Arduino sketch's name and files (name → text): the .ino picked and the sketch files
/// beside it, or every sketch file in the folder picked. Null when cancelled.
Future<(String, Map<String, String>)?> pickSketch() async {
  final paths = await _channel.invokeListMethod<String>('pickSketch');
  if (paths == null || paths.isEmpty) return null;
  final picked = paths.first;
  final isFolder = FileSystemEntity.isDirectorySync(picked);
  final dir = Directory(isFolder ? picked : File(picked).parent.path);
  final files = <String, String>{};
  if (!isFolder) files[_name(picked)] = await _read(File(picked));
  try {
    // With an .ino picked, the sandbox may not let the app read the files beside it: then it is the .ino alone.
    await for (final e in dir.list()) {
      if (e is File && isSketchFile(_name(e.path)) && !files.containsKey(_name(e.path))) files[_name(e.path)] = await _read(e);
    }
  } catch (_) {}
  final name = isFolder ? _name(picked) : _name(picked).replaceAll(RegExp(r'\.ino$', caseSensitive: false), '');
  return (name, files);
}

String _name(String path) => path.split(Platform.pathSeparator).last;

Future<String> _read(File f) async => utf8.decode(await f.readAsBytes(), allowMalformed: true);

/// What was last written to (or read from) a project's folder, so only changes are written.
class _Saved {
  _Saved(this.folder, this.files, this.meta);
  final String folder;
  final Map<String, String> files;
  final String meta;
}

/// A project as it is to be written: taken when [FolderStore.write] is called, as the project keeps changing.
typedef _Snapshot = ({String id, String folder, List<(String, String)> files, String meta});

class FolderStore implements ProjectFolder {
  FolderStore(this.path);

  @override
  final String path;

  final _saved = <String, _Saved>{};
  Future<void> _queue = Future.value();

  /// Waits for the writes asked for so far (for tests).
  @visibleForTesting
  Future<void> flush() => _queue;

  String _dir(String folder) => '$path/$folder';

  @override
  Future<List<Project>> readAll({required String defaultBoard}) async {
    final root = Directory(path);
    await root.create(recursive: true);
    final dirs = (await root.list().toList()).whereType<Directory>().where((d) => !_name(d.path).startsWith('.')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = <Project>[];
    final ids = <String>{};
    for (final d in dirs) {
      final folder = _name(d.path);
      try {
        final files = <String, String>{};
        await for (final e in d.list()) {
          if (e is File && isSketchFile(_name(e.path))) files[_name(e.path)] = await _read(e);
        }
        final metaFile = File('${d.path}/$kProjectMetaFile');
        Project p;
        var meta = '';
        if (await metaFile.exists()) {
          meta = await metaFile.readAsString();
          p = projectFromMeta(meta, files);
        } else if (files.keys.any((n) => n.toLowerCase() == '${folder.toLowerCase()}.ino')) {
          // A plain Arduino sketch (made in the Arduino IDE, or copied in): a code project.
          p = projectFromSketch(folder, files, board: defaultBoard, updated: (await d.stat()).modified.millisecondsSinceEpoch);
        } else {
          continue; // not a sketch: left alone
        }
        if (!ids.add(p.id)) {
          // A project folder copied in Finder: a project of its own.
          p.id = uid();
          meta = '';
        }
        _saved[p.id] = _Saved(folder, {for (final f in p.files) f.name: f.content}, meta);
        out.add(p);
      } catch (e) {
        debugPrint('RoboCore: left $folder alone, it could not be read: $e'); // never changed or removed
      }
    }
    return out;
  }

  @override
  void write(List<Project> projects) {
    final snap = <_Snapshot>[
      for (final p in projects)
        (
          id: p.id,
          folder: sketchFolderName(p.files.first.name),
          files: [for (final f in p.files) (f.name, f.content)],
          meta: projectMeta(p),
        ),
    ];
    _queue = _queue.then((_) => _write(snap)).catchError((Object e) {
      debugPrint('RoboCore: could not save to $path: $e');
    });
  }

  Future<void> _write(List<_Snapshot> projects) async {
    // Each project keeps its folder while its main file's name doesn't change; a new or renamed one gets a folder
    // nothing else uses (a number on the end if it must), never one that is there already.
    final taken = {for (final s in _saved.values) s.folder.toLowerCase()};
    final folders = <String, String>{};
    for (final p in projects) {
      final prev = _saved[p.id];
      if (prev != null && prev.folder.toLowerCase() == p.folder.toLowerCase()) folders[p.id] = prev.folder;
    }
    for (final p in projects.where((p) => !folders.containsKey(p.id))) {
      var name = p.folder;
      for (var n = 2; taken.contains(name.toLowerCase()) || await Directory(_dir(name)).exists(); n++) {
        name = '${p.folder}_$n';
      }
      taken.add(name.toLowerCase());
      folders[p.id] = name;
    }

    for (final p in projects) {
      final name = folders[p.id]!;
      final prev = _saved[p.id];
      final dir = Directory(_dir(name));
      if (prev != null && prev.folder != name && await Directory(_dir(prev.folder)).exists()) {
        await Directory(_dir(prev.folder)).rename(dir.path); // its main file was renamed
      }
      await dir.create(recursive: true);
      final files = <String, String>{};
      for (final (n, text) in p.files) {
        if (!isSketchFile(n)) continue;
        files[n] = text;
        if (prev?.files[n] != text || prev?.folder != name) await File('${dir.path}/$n').writeAsString(text);
      }
      // A tab deleted in RoboCore: its file goes too (only files RoboCore wrote or read there).
      for (final n in prev?.files.keys ?? const <String>[]) {
        if (!files.containsKey(n)) {
          final f = File('${dir.path}/$n');
          if (await f.exists()) await f.delete();
        }
      }
      if (prev?.meta != p.meta || prev?.folder != name) await File('${dir.path}/$kProjectMetaFile').writeAsString(p.meta);
      _saved[p.id] = _Saved(name, files, p.meta);
    }
  }

  @override
  Future<void> remove(Project p) async {
    await _queue;
    final s = _saved.remove(p.id);
    if (s == null) return;
    try {
      await _channel.invokeMethod<bool>('trash', {'path': _dir(s.folder)});
    } catch (e) {
      debugPrint('RoboCore: could not move ${s.folder} to the Trash: $e');
    }
  }

  @override
  Future<void> reveal([Project? p]) async {
    await _queue;
    final s = p == null ? null : _saved[p.id];
    await _channel.invokeMethod<void>('reveal', {'path': s == null ? path : _dir(s.folder)});
  }

  @override
  Future<void> forget() async {
    await _queue;
    try {
      await _channel.invokeMethod<void>('forget');
    } catch (_) {}
  }
}
