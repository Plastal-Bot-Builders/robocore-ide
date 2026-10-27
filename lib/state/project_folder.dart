// Projects kept as files (the macOS app's projects folder): each project is a sketch folder named after its
// main .ino, as the Arduino IDE expects (TrafficLight/TrafficLight.ino, config.h …), plus a hidden
// .robocore.json with what the files don't hold (the blocks, the board, the project's name …).
// lib/hw/sketchbook_native.dart reads and writes them; this file is the format, without any file access.
import 'dart:convert';

import 'models.dart';

/// The hidden file in each project folder.
const kProjectMetaFile = '.robocore.json';

/// Where the projects live when they are files.
abstract class ProjectFolder {
  /// The folder, e.g. /Users/you/Documents/RoboCore.
  String get path;

  /// Every project in the folder: RoboCore projects, and plain Arduino sketch folders (Name/Name.ino) as code
  /// projects on [defaultBoard].
  Future<List<Project>> readAll({required String defaultBoard});

  /// Writes what changed since the last write (or read). Queued: returns at once.
  void write(List<Project> projects);

  /// Moves the project's folder to the Trash.
  Future<void> remove(Project p);

  /// Shows the project's folder (or the projects folder) in Finder.
  Future<void> reveal([Project? p]);

  /// Stops using this folder; the files stay where they are.
  Future<void> forget();
}

/// The C++ files a sketch folder can hold.
bool isSketchFile(String name) => RegExp(r'^[^./\\][^/\\]*\.(ino|h|hpp|c|cpp)$', caseSensitive: false).hasMatch(name);

/// The folder name for a main file: its name without .ino, in the characters Arduino allows in sketch names.
String sketchFolderName(String mainFile) {
  final base = mainFile.replaceAll(RegExp(r'\.ino$', caseSensitive: false), '').replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return base.isEmpty || base.startsWith('.') ? 'Sketch' : base;
}

/// The hidden file's contents: the project without its files' text (the files are on disk), and the files' order.
String projectMeta(Project p) {
  final j = p.toJson()..['files'] = [for (final f in p.files) f.name];
  return const JsonEncoder.withIndent('  ').convert({'app': 'RoboCore IDE', 'v': 1, ...j});
}

/// A project from its hidden file and the files read from its folder (name → text).
Project projectFromMeta(String meta, Map<String, String> files) {
  final j = (jsonDecode(meta) as Map).cast<String, dynamic>();
  final listed = [for (final n in (j['files'] as List? ?? const [])) '$n'];
  final names = [
    for (final n in listed)
      if (files.containsKey(n)) n,
    // Files added outside RoboCore (in Finder or the Arduino IDE) come after the others.
    ...(files.keys.where((n) => !listed.contains(n)).toList()..sort()),
  ];
  if (names.isEmpty) throw const FormatException('no files');
  j['files'] = [
    for (final n in names) {'name': n, 'content': files[n]}
  ];
  return Project.fromJson(j);
}

/// A plain Arduino sketch folder (no hidden file) as a code project: the main .ino first, then the others.
Project projectFromSketch(String folder, Map<String, String> files, {required String board, required int updated}) {
  final main = files.keys.firstWhere((n) => n.toLowerCase() == '${folder.toLowerCase()}.ino');
  return Project(
    id: uid(),
    name: folder,
    board: board,
    mode: 'code',
    setup: [],
    loop: [],
    files: [
      ProjectFile(main, files[main]!),
      for (final n in files.keys.where((n) => n != main).toList()..sort()) ProjectFile(n, files[n]!),
    ],
    codeEdited: true,
    autosave: true,
    updated: updated,
  );
}
