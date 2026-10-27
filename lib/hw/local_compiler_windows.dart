// Real compiles on this computer (the Windows app): arduino-cli, as the compile server runs it
// (server/src/compile.js), with the answer in the same shape (ServerBuild), so Verify and Upload work the same.
// local_compiler_native.dart hands it out on Windows.
import 'dart:convert';
import 'dart:io';

import '../engine/compiler.dart' show SourceFile;
import 'arduino_cli.dart';
import 'compile_client.dart' show LocalBuilder, ServerBuild;

class WindowsBuilder implements LocalBuilder {
  final _cli = ArduinoCli.instance;

  @override
  bool canBuild(String board) => _cli.supported && kFqbn.containsKey(board);

  @override
  Future<ServerBuild> compile({required String board, required List<SourceFile> files, void Function(String line)? onLog}) async {
    final log = onLog ?? (String _) {};
    final fqbn = kFqbn[board];
    if (fqbn == null) return ServerBuild.failed('This board can’t be compiled on this computer yet.');
    try {
      await _cli.ensureAll(board, log);
    } on CliError catch (e) {
      return ServerBuild.failed(e.message, retry: true);
    } catch (e) {
      return ServerBuild.failed('Could not set up the Arduino compiler: $e', retry: true);
    }
    final started = DateTime.now();
    final work = await Directory.systemTemp.createTemp('rc-');
    final main = files.firstWhere((f) => f.name.endsWith('.ino'), orElse: () => files.first).name;
    final sketchName = main.replaceAll(RegExp(r'\.ino$'), '');
    final sketchDir = '${work.path}\\$sketchName';
    final buildDir = '${work.path}\\build';
    try {
      await Directory(sketchDir).create(recursive: true);
      await Directory(buildDir).create(recursive: true);
      for (final f in files) {
        await File('$sketchDir\\${f.name}').writeAsString(f.content);
      }
      final r = await _cli.run([
        'compile',
        '--fqbn', fqbn,
        '--build-path', buildDir,
        if (Directory(_cli.libraryDir).existsSync()) ...['--library', _cli.libraryDir],
        '--warnings', 'default',
        '--format', 'json',
        sketchDir,
      ], workingDirectory: work.path);
      final result = parseCliJson('${r.stdout}');
      if (result == null) {
        final detail = '${r.stderr}${r.stdout}'.trim();
        return ServerBuild.failed('arduino-cli gave no result${detail.isEmpty ? '' : ': ${_tail(detail)}'}');
      }
      String clean(Object? s) => '${s ?? ''}'.replaceAll('$sketchDir\\', '').replaceAll(sketchDir, sketchName).replaceAll(buildDir, '<build>');
      final out = clean(result['compiler_out']), err = clean(result['compiler_err']);
      final names = [for (final f in files) f.name];
      final br = result['builder_result'] is Map ? (result['builder_result'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      var problems = mergeProblems(parseStructured(br['diagnostics'], sketchDir, names), parseDiagnostics('$err\n$out', sketchDir, names));
      problems.sort((a, b) => a['severity'] == b['severity'] ? 0 : (a['severity'] == 'error' ? -1 : 1));
      final logText = '$out${err.isEmpty ? '' : '\n$err'}'.trim();
      final elapsed = DateTime.now().difference(started).inMilliseconds;

      if (result['success'] != true) {
        if (!problems.any((p) => p['severity'] == 'error')) {
          problems = [
            {'severity': 'error', 'file': main, 'line': 1, 'message': clean(result['error'] ?? 'Compilation failed.')},
            ...problems,
          ];
        }
        return ServerBuild.fromJson({'ok': false, 'problems': problems, 'log': logText, 'elapsedMs': elapsed}, mainFile: main);
      }

      Map<String, dynamic> image;
      if (board == 'uno') {
        image = {'format': 'hex', 'data': await File('$buildDir\\$main.hex').readAsString()};
      } else {
        final paths = {
          'bootloader': '$buildDir\\$main.bootloader.bin',
          'partitions': '$buildDir\\$main.partitions.bin',
          'boot_app0': _cli.bootApp0(),
          'app': '$buildDir\\$main.bin',
        };
        final parts = <Map<String, dynamic>>[];
        for (final (name, offset) in esp32Parts(board)) {
          final p = paths[name];
          if (p == null || !File(p).existsSync()) return ServerBuild.failed('The build has no $name image.');
          final data = await File(p).readAsBytes();
          parts.add({'name': name, 'offset': offset, 'size': data.length, 'data': base64Encode(data)});
        }
        image = {'format': 'esp32', 'chip': board == 'v2' ? 'esp32s3' : 'esp32', 'flashSize': board == 'v2' ? '8MB' : '4MB', 'parts': parts};
      }
      return ServerBuild.fromJson({
        'ok': true,
        'problems': problems,
        'sizes': parseSizes(br, out),
        'log': logText,
        'image': image,
        'elapsedMs': elapsed,
      }, mainFile: main);
    } catch (e) {
      return ServerBuild.failed('Compiling on this computer failed: $e');
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }
}

String _tail(String s) => s.length > 1500 ? s.substring(s.length - 1500) : s;

// ---- arduino-cli output, as in server/src/parse.js ----

final _diag = RegExp(r'^(.*?):(\d+):(?:(\d+):)?\s*(fatal error|error|warning|note):\s*(.*)$');
final _link = RegExp('undefined reference to [`\'"]?([^`\'"]+)[`\'"]?');

String _base(String path) => path.split(RegExp(r'[/\\]')).last;
String _source(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  return parts.sublist(parts.length < 2 ? 0 : parts.length - 2).join('/');
}

String? _fileIn(String path, String sketchDir, Set<String> names) {
  if (path.toLowerCase().startsWith(sketchDir.toLowerCase())) return path.substring(sketchDir.length).replaceFirst(RegExp(r'^[/\\]+'), '');
  final b = _base(path);
  return names.contains(b) ? b : null;
}

List<Map<String, dynamic>> parseDiagnostics(String text, String sketchDir, List<String> sketchFiles) {
  final problems = <Map<String, dynamic>>[];
  final seen = <String>{};
  final names = sketchFiles.toSet();
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    var m = _diag.firstMatch(line);
    if (m != null) {
      final path = m.group(1)!, sev = m.group(4)!;
      if (sev == 'note') continue;
      final file = _fileIn(path, sketchDir, names);
      final p = <String, dynamic>{
        'severity': sev == 'warning' ? 'warning' : 'error',
        'file': file ?? 'library',
        'line': int.parse(m.group(2)!),
        'column': m.group(3) == null ? null : int.parse(m.group(3)!),
        'message': m.group(5)!.trim(),
        if (file == null) 'source': _source(path),
      };
      if (seen.add('${p['severity']}|${p['file']}|${p['line']}|${p['message']}')) problems.add(p);
      continue;
    }
    m = _link.firstMatch(line);
    if (m != null) {
      final sym = m.group(1)!.trim();
      if (!seen.add('link|$sym')) continue;
      final friendly = const ['setup()', 'loop()', 'setup', 'loop'].contains(sym)
          ? 'Every sketch needs a ${sym.replaceAll('()', '')}() function.'
          : '$sym is used but never defined (missing function body or library?).';
      problems.add({'severity': 'error', 'file': sketchFiles.isEmpty ? null : sketchFiles.first, 'line': 1, 'message': "undefined reference to '$sym'. $friendly"});
    }
  }
  return problems;
}

List<Map<String, dynamic>> parseStructured(Object? diags, String sketchDir, List<String> sketchFiles) {
  if (diags is! List) return [];
  final names = sketchFiles.toSet();
  final out = <Map<String, dynamic>>[];
  for (final d in diags) {
    if (d is! Map) continue;
    final sev = '${d['severity'] ?? ''}'.toLowerCase();
    if (sev.contains('note')) continue;
    final path = '${d['file'] ?? ''}';
    final file = path.isEmpty ? null : _fileIn(path, sketchDir, names);
    final msg = '${d['message'] ?? ''}'.trim();
    if (msg.isEmpty) continue;
    out.add({
      'severity': sev.contains('warn') ? 'warning' : 'error',
      'file': file ?? 'library',
      'line': (d['line'] is num ? (d['line'] as num).toInt() : 0) == 0 ? 1 : (d['line'] as num).toInt(),
      'column': d['column'] is num && (d['column'] as num) > 0 ? (d['column'] as num).toInt() : null,
      'message': msg,
      if (file == null && path.isNotEmpty) 'source': _source(path),
    });
  }
  return out;
}

List<Map<String, dynamic>> mergeProblems(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  final seen = <String>{};
  return [
    for (final p in [...a, ...b])
      if (seen.add('${p['severity']}|${p['file']}|${p['line']}|${'${p['message']}'.split('\n').first.trim()}')) p
  ];
}

Map<String, dynamic> parseSizes(Map<String, dynamic> builderResult, String compilerOut) {
  final sizes = <String, dynamic>{};
  final sections = builderResult['executable_sections_size'];
  if (sections is List) {
    for (final s in sections) {
      if (s is! Map) continue;
      if (s['name'] == 'text') sizes['flash'] = {'used': s['size'], 'max': s['max_size']};
      if (s['name'] == 'data') sizes['ram'] = {'used': s['size'], 'max': s['max_size']};
    }
  }
  if (!sizes.containsKey('flash')) {
    final m = RegExp(r'Sketch uses (\d+) bytes .*?Maximum is (\d+) bytes').firstMatch(compilerOut);
    if (m != null) sizes['flash'] = {'used': int.parse(m.group(1)!), 'max': int.parse(m.group(2)!)};
  }
  if (!sizes.containsKey('ram')) {
    final m = RegExp(r'Global variables use (\d+) bytes .*?Maximum is (\d+) bytes').firstMatch(compilerOut);
    if (m != null) sizes['ram'] = {'used': int.parse(m.group(1)!), 'max': int.parse(m.group(2)!)};
  }
  return sizes;
}

/// arduino-cli's JSON can follow other text: take the last JSON object.
Map<String, dynamic>? parseCliJson(String stdout) {
  final s = stdout.trim();
  Map<String, dynamic>? tryParse(String t) {
    try {
      final j = jsonDecode(t);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  final whole = tryParse(s);
  if (whole != null) return whole;
  final i = s.lastIndexOf('\n{');
  if (i >= 0) {
    final r = tryParse(s.substring(i + 1));
    if (r != null) return r;
  }
  final j = s.indexOf('{');
  return j >= 0 ? tryParse(s.substring(j)) : null;
}
