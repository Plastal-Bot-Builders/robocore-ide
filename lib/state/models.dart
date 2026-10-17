import 'dart:convert';
import 'dart:math' as math;

import '../data/catalog.dart';
import '../engine/codegen.dart';

final _rnd = math.Random();
String uid() => List.generate(8, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rnd.nextInt(36)]).join();

typedef Block = Map<String, dynamic>;

List<Block> cloneBlocks(dynamic list) =>
    [for (final b in (list as List? ?? const [])) Map<String, dynamic>.from(b as Map)];

class ProjectFile {
  String name;
  String content;
  ProjectFile(this.name, this.content);
  Map<String, dynamic> toJson() => {'name': name, 'content': content};
  factory ProjectFile.fromJson(Map<String, dynamic> j) => ProjectFile(j['name'] as String, j['content'] as String? ?? '');
}

class Project {
  String id;
  String name;
  String board;
  String mode; // blocks | code
  List<Block> setup;
  List<Block> loop;
  List<ProjectFile> files;
  bool codeEdited;
  bool autosave;
  int updated;
  bool dirty = false;

  Project({
    required this.id,
    required this.name,
    required this.board,
    required this.mode,
    required this.setup,
    required this.loop,
    required this.files,
    required this.codeEdited,
    required this.autosave,
    required this.updated,
  });

  bool get hasBlocks => mode == 'blocks' || !codeEdited;
  List<Block> stack(String s) => s == 'setup' ? setup : loop;

  String generate() => genBlocks(name, setup, loop, board: board);
  void syncCode() {
    if (!codeEdited) files.first.content = generate();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'board': board,
        'mode': mode,
        'blocks': {'setup': setup, 'loop': loop},
        'files': files.map((f) => f.toJson()).toList(),
        'codeEdited': codeEdited,
        'autosave': autosave,
        'updated': updated,
      };

  factory Project.fromJson(Map<String, dynamic> j) {
    final b = (j['blocks'] as Map?) ?? const {};
    return Project(
      id: j['id'] as String,
      name: j['name'] as String,
      board: j['board'] as String? ?? 'v2',
      mode: j['mode'] as String? ?? 'code',
      setup: cloneBlocks(b['setup']),
      loop: cloneBlocks(b['loop']),
      files: [for (final f in (j['files'] as List)) ProjectFile.fromJson((f as Map).cast<String, dynamic>())],
      codeEdited: j['codeEdited'] as bool? ?? true,
      autosave: j['autosave'] as bool? ?? true,
      updated: (j['updated'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Project copy() => Project.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

String fileBase(String n) {
  final words = n.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final s = words.map((w) => w[0].toUpperCase() + w.substring(1)).join();
  return s.isEmpty ? 'Sketch' : s;
}

Project projectFrom(Example ex, {String? name, String board = 'v2', String? mode, int? updated}) {
  final nm = name ?? ex.proj;
  final blocks = ex.blocksFor(board);
  final code = ex.codeFor(board);
  final hasBlocks = blocks != null;
  final m = (mode != null && (mode == 'code' || hasBlocks)) ? mode : (hasBlocks ? 'blocks' : 'code');
  final p = Project(
    id: uid(),
    name: nm,
    board: board,
    mode: m,
    setup: cloneBlocks(blocks?['setup']),
    loop: cloneBlocks(blocks?['loop']),
    files: [ProjectFile('${ex.file ?? fileBase(nm)}.ino', code), ProjectFile('config.h', kConfigH)],
    codeEdited: !hasBlocks,
    autosave: true,
    updated: updated ?? DateTime.now().millisecondsSinceEpoch,
  );
  if (hasBlocks && (m == 'blocks' || code.isEmpty)) p.files.first.content = p.generate();
  if (hasBlocks && code.isNotEmpty && m == 'code') p.codeEdited = true;
  return p;
}

class Settings {
  String theme;
  int fontSize;
  bool autocomplete, wrap, autosave;
  String lang;

  /// The compile server (server/ in this repo) that builds sketches for a real board. Empty = not set.
  String compileServer;
  Settings({
    this.theme = 'paper',
    this.fontSize = 13,
    this.autocomplete = true,
    this.wrap = false,
    this.autosave = true,
    this.lang = 'English',
    this.compileServer = '',
  });
  Map<String, dynamic> toJson() => {
        'theme': theme,
        'fontSize': fontSize,
        'autocomplete': autocomplete,
        'wrap': wrap,
        'autosave': autosave,
        'lang': lang,
        'compileServer': compileServer,
      };
  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        theme: j['theme'] as String? ?? 'paper',
        fontSize: (j['fontSize'] as num?)?.toInt() ?? 13,
        autocomplete: j['autocomplete'] as bool? ?? true,
        wrap: j['wrap'] as bool? ?? false,
        autosave: j['autosave'] as bool? ?? true,
        lang: j['lang'] as String? ?? 'English',
        compileServer: j['compileServer'] as String? ?? '',
      );
}

class LogLine {
  final String t, text, dir; // dir: out | in | sys | err
  const LogLine(this.t, this.text, this.dir);
}

class OutLine {
  final String t, text, kind; // '' | info | ok | err | sys
  const OutLine(this.t, this.text, this.kind);
}

String two(int n) => n.toString().padLeft(2, '0');
String clock([DateTime? d]) {
  final x = d ?? DateTime.now();
  return '${two(x.hour)}:${two(x.minute)}';
}

String stamp() {
  final d = DateTime.now();
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}.${d.millisecond.toString().padLeft(3, '0')}';
}

String ago(int t) {
  final s = (DateTime.now().millisecondsSinceEpoch - t) / 1000;
  if (s < 60) return 'just now';
  final m = s / 60;
  if (m < 60) return '${m.round()} min ago';
  final h = m / 60;
  if (h < 24) return '${h.round()}h ago';
  final d = h / 24;
  if (d < 2) return 'yesterday';
  if (d < 7) return '${d.round()} days ago';
  if (d < 14) return 'last week';
  if (d < 30) return '${(d / 7).round()} weeks ago';
  if (d < 60) return 'last month';
  return '${(d / 30).round()} months ago';
}

String fmtN(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
