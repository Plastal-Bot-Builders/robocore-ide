// Compiling on this Mac, as the Arduino IDE does: arduino-cli inside RoboCore.app (Contents/MacOS/arduino-cli),
// and each board's tools in RoboCore's own Arduino15 folder (~/Library/Application Support/RoboCore), apart from
// the Arduino IDE's, fetched once the first time that board is built.
// After that it needs no internet and no compile server. The steps and the output it returns are those of the
// compile server (server/src/compile.js and parse.js), so the IDE treats both the same.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/compiler.dart' show SourceFile;
import 'compile_client.dart';

/// What this Mac can build: the board's FQBN, its arduino-cli platform, and how much it takes once fetched.
const _boards = {
  'uno': (fqbn: 'arduino:avr:uno', core: 'arduino:avr', name: 'Arduino Uno', size: 'about 240 MB'),
};

/// The arduino-cli in the app, or null when this build has none.
LocalBuilder? localBuilder() {
  if (defaultTargetPlatform != TargetPlatform.macOS) return null;
  final cli = File('${File(Platform.resolvedExecutable).parent.path}/arduino-cli');
  return cli.existsSync() ? _ArduinoCli(cli.path) : null;
}

class _ArduinoCli implements LocalBuilder {
  _ArduinoCli(this.cli);
  final String cli;
  final _ready = <String>{};

  @override
  bool canBuild(String board) => _boards.containsKey(board);

  static final _home = Platform.environment['HOME'] ?? '';
  static final _data = '$_home/Library/Application Support/RoboCore';

  /// Only what arduino-cli needs, with RoboCore's own folders, so an installed Arduino IDE is never touched.
  Map<String, String> get _env => {
        'HOME': _home,
        'TMPDIR': Directory.systemTemp.path,
        'PATH': '/usr/bin:/bin',
        'LANG': 'C.UTF-8',
        'ARDUINO_DIRECTORIES_DATA': '$_data/Arduino15',
        'ARDUINO_DIRECTORIES_DOWNLOADS': '$_data/Arduino15/staging',
        'ARDUINO_DIRECTORIES_USER': '$_data/Arduino',
        'ARDUINO_BUILD_CACHE_PATH': '$_home/Library/Caches/RoboCore/arduino',
      };

  Future<ProcessResult> _run(List<String> args, {String? cwd}) =>
      Process.run(cli, args, environment: _env, includeParentEnvironment: false, workingDirectory: cwd);

  /// Runs arduino-cli and hands each line it prints to [onLog].
  Future<int> _stream(List<String> args, void Function(String line)? onLog) async {
    final p = await Process.start(cli, args, environment: _env, includeParentEnvironment: false);
    void lines(Stream<List<int>> s) => s.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
          final t = l.split('\r').last.trim();
          if (t.isNotEmpty) onLog?.call(t);
        });
    lines(p.stdout);
    lines(p.stderr);
    return p.exitCode;
  }

  /// The board's platform, fetched the first time (the only step that needs the internet). An error, or null.
  Future<String?> _ensure(String core, String name, String size, void Function(String line)? onLog) async {
    if (_ready.contains(core)) return null;
    final list = await _run(['core', 'list', '--format', 'json']);
    if (list.exitCode == 0 && '${list.stdout}'.contains('"$core"')) {
      _ready.add(core);
      return null;
    }
    onLog?.call('Getting the $name tools, once ($size on this Mac). After this, compiling for it needs no internet.');
    if (await _stream(['core', 'update-index'], onLog) != 0 || await _stream(['core', 'install', core], onLog) != 0) {
      return 'Could not get the $name tools. Check the internet connection, then try again.';
    }
    _ready.add(core);
    return null;
  }

  @override
  Future<ServerBuild> compile({required String board, required List<SourceFile> files, void Function(String line)? onLog}) async {
    final b = _boards[board];
    if (b == null) return ServerBuild.failed('This Mac can’t build for $board yet.');
    final started = DateTime.now();
    try {
      final missing = await _ensure(b.core, b.name, b.size, onLog);
      if (missing != null) return ServerBuild.failed(missing, retry: true);
    } catch (e) {
      return ServerBuild.failed('Could not run the compiler in RoboCore: $e');
    }

    final main = files.first.name;
    final name = main.replaceAll(RegExp(r'\.ino$'), '');
    final work = await Directory.systemTemp.createTemp('rc-');
    final sketch = Directory('${work.path}/$name');
    final build = Directory('${work.path}/build');
    try {
      await sketch.create();
      await build.create();
      for (final f in files) {
        await File('${sketch.path}/${f.name}').writeAsString(f.content);
      }
      final r = await _run([
        'compile', '--fqbn', b.fqbn, '--build-path', build.path, '--warnings', 'default', '--format', 'json', sketch.path,
      ], cwd: work.path);
      final result = parseCliJson('${r.stdout}');
      if (result == null) {
        final said = '${r.stderr}${r.stdout}'.trim();
        return ServerBuild.failed('The compiler gave no result${said.isEmpty ? '' : ': ${said.split('\n').last}'}');
      }
      final names = [for (final f in files) f.name];
      String clean(Object? t) => '${t ?? ''}'.replaceAll('${sketch.path}/', '').replaceAll(sketch.path, name).replaceAll(work.path, '');
      final out = clean(result['compiler_out']), err = clean(result['compiler_err']);
      var problems = mergeProblems(
        parseStructured((result['builder_result'] as Map?)?['diagnostics'], sketch.path, names),
        parseDiagnostics('$err\n$out', names),
      )..sort((a, b) => (a['severity'] == b['severity'] ? 0 : (a['severity'] == 'error' ? -1 : 1)));
      final log = '$out${err.isEmpty ? '' : '\n$err'}'.trim();
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (result['success'] != true) {
        if (!problems.any((p) => p['severity'] == 'error')) {
          problems = [
            {'severity': 'error', 'file': main, 'line': 1, 'message': clean(result['error'] ?? 'Compilation failed.')},
            ...problems,
          ];
        }
        return ServerBuild.fromJson({'ok': false, 'problems': problems, 'log': log, 'elapsedMs': ms}, mainFile: main);
      }
      final hex = await File('${build.path}/$main.hex').readAsString();
      return ServerBuild.fromJson({
        'ok': true,
        'problems': problems,
        'sizes': parseSizes(result, out),
        'log': log,
        'image': {'format': 'hex', 'data': hex},
        'elapsedMs': ms,
      }, mainFile: main);
    } catch (e) {
      return ServerBuild.failed('Compiling on this Mac failed: $e');
    } finally {
      unawaited(work.delete(recursive: true).then<Object?>((_) => null, onError: (Object _) => null));
    }
  }
}

// ---------------------------------------------------------------- arduino-cli's output (as server/src/parse.js)

final _diag = RegExp(r'^(.*?):(\d+):(?:(\d+):)?\s*(fatal error|error|warning|note):\s*(.*)$');
final _link = RegExp('undefined reference to [`\'"]?([^`\'"]+)[`\'"]?');

String _base(String path) => path.split(RegExp(r'[/\\]')).last;

String _source(String path) => path.split(RegExp(r'[/\\]')).reversed.take(2).toList().reversed.join('/');

/// arduino-cli --format json can print other text first: the last JSON object.
@visibleForTesting
Map<String, dynamic>? parseCliJson(String stdout) {
  final s = stdout.trim();
  for (final from in [0, s.lastIndexOf('\n{') + 1, s.indexOf('{')]) {
    if (from < 0 || from >= s.length) continue;
    try {
      return (jsonDecode(s.substring(from)) as Map).cast<String, dynamic>();
    } catch (_) {}
  }
  return null;
}

/// Problems from the compiler's and linker's text, for the user's files ([names]) or 'library'.
@visibleForTesting
List<Map<String, dynamic>> parseDiagnostics(String text, List<String> names) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    final m = _diag.firstMatch(line);
    if (m != null) {
      if (m[4] == 'note') continue;
      final path = m[1]!;
      final file = names.contains(_base(path)) ? _base(path) : null;
      final p = <String, dynamic>{
        'severity': m[4] == 'warning' ? 'warning' : 'error',
        'file': file ?? 'library',
        'line': int.parse(m[2]!),
        if (m[3] != null) 'column': int.parse(m[3]!),
        'message': m[5]!.trim(),
        if (file == null) 'source': _source(path),
      };
      if (seen.add('${p['severity']}|${p['file']}|${p['line']}|${p['message']}')) out.add(p);
      continue;
    }
    final l = _link.firstMatch(line);
    if (l != null) {
      final sym = l[1]!.trim();
      if (!seen.add('link|$sym')) continue;
      final core = sym.replaceAll('()', '');
      final friendly = core == 'setup' || core == 'loop'
          ? 'Every sketch needs a $core() function.'
          : '$sym is used but never defined (missing function body or library?).';
      out.add({'severity': 'error', 'file': names.isEmpty ? null : names.first, 'line': 1, 'message': "undefined reference to '$sym'. $friendly"});
    }
  }
  return out;
}

/// Problems from arduino-cli's builder_result.diagnostics (preferred when it has them).
@visibleForTesting
List<Map<String, dynamic>> parseStructured(Object? diags, String sketchDir, List<String> names) {
  if (diags is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final d in diags) {
    if (d is! Map) continue;
    final sev = '${d['severity'] ?? ''}'.toLowerCase();
    if (sev.contains('note')) continue;
    final path = '${d['file'] ?? ''}';
    String? file;
    if (path.startsWith(sketchDir)) {
      file = path.substring(sketchDir.length).replaceFirst(RegExp(r'^[/\\]+'), '');
    } else if (names.contains(_base(path))) {
      file = _base(path);
    }
    final msg = '${d['message'] ?? ''}'.trim();
    if (msg.isEmpty) continue;
    out.add({
      'severity': sev.contains('warn') ? 'warning' : 'error',
      'file': file ?? 'library',
      'line': (d['line'] as num?)?.toInt() ?? 1,
      if ((d['column'] as num?) != null) 'column': (d['column'] as num).toInt(),
      'message': msg,
      if (file == null && path.isNotEmpty) 'source': _source(path),
    });
  }
  return out;
}

/// [a] then [b] without repeats (the text log repeats a diagnostic with the code under it: first lines compared).
@visibleForTesting
List<Map<String, dynamic>> mergeProblems(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  final seen = <String>{};
  return [
    for (final p in [...a, ...b])
      if (seen.add('${p['severity']}|${p['file']}|${p['line']}|${'${p['message']}'.split('\n').first.trim()}')) p,
  ];
}

/// Program and RAM use, from builder_result or the text summary.
@visibleForTesting
Map<String, dynamic> parseSizes(Map<String, dynamic> result, String compilerOut) {
  final sizes = <String, dynamic>{};
  final sections = (result['builder_result'] as Map?)?['executable_sections_size'];
  if (sections is List) {
    for (final s in sections.whereType<Map>()) {
      if (s['name'] == 'text') sizes['flash'] = {'used': s['size'], 'max': s['max_size']};
      if (s['name'] == 'data') sizes['ram'] = {'used': s['size'], 'max': s['max_size']};
    }
  }
  final f = RegExp(r'Sketch uses (\d+) bytes .*?Maximum is (\d+) bytes').firstMatch(compilerOut);
  if (sizes['flash'] == null && f != null) sizes['flash'] = {'used': int.parse(f[1]!), 'max': int.parse(f[2]!)};
  final r = RegExp(r'Global variables use (\d+) bytes .*?Maximum is (\d+) bytes').firstMatch(compilerOut);
  if (sizes['ram'] == null && r != null) sizes['ram'] = {'used': int.parse(r[1]!), 'max': int.parse(r[2]!)};
  return sizes;
}
