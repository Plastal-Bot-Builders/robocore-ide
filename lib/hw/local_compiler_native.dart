// Compiling on this Mac, as the Arduino IDE does, with no internet and no compile server: arduino-cli inside
// RoboCore.app (Contents/MacOS/arduino-cli) and, from the DMG, the board tools and libraries for this kind of Mac
// (Contents/Resources/Offline, made by tools/make_offline_bundle.sh). A board's tools are unpacked into RoboCore's own
// Arduino15 folder (~/Library/Application Support/RoboCore, never the Arduino IDE's) the first time it is built. A
// build without that folder (a developer's) fetches the Uno's tools from the internet instead, once.
// The steps and the output it returns are those of the compile server (server/src/compile.js, boards.js, parse.js),
// so the IDE treats both the same.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/compiler.dart' show SourceFile;
import 'compile_client.dart';

/// What this Mac can build (server/src/boards.js): the FQBN, the offline pack with its tools, and for the ESP32s
/// where each part of the program goes in flash.
const _boards = {
  'uno': (fqbn: 'arduino:avr:uno', pack: 'uno', core: 'arduino:avr', name: 'Arduino Uno', chip: '', bootloader: 0, flash: ''),
  'v2': (
    fqbn: 'esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=enabled,CPUFreq=240',
    pack: 'esp32', core: 'esp32:esp32', name: 'RoboCore V2', chip: 'esp32s3', bootloader: 0x0, flash: '8MB',
  ),
  'devkit': (
    fqbn: 'esp32:esp32:esp32:FlashSize=4M,PartitionScheme=default',
    pack: 'esp32', core: 'esp32:esp32', name: 'ESP32 DevKit', chip: 'esp32', bootloader: 0x1000, flash: '4MB',
  ),
  'nodemcu': (
    fqbn: 'esp32:esp32:nodemcu-32s', pack: 'esp32', core: 'esp32:esp32', name: 'NodeMCU-32S', chip: 'esp32', bootloader: 0x1000, flash: '4MB',
  ),
};

/// The arduino-cli in the app, or null when this build has none.
LocalBuilder? localBuilder() {
  if (defaultTargetPlatform != TargetPlatform.macOS) return null;
  final macos = File(Platform.resolvedExecutable).parent.path;
  final cli = File('$macos/arduino-cli');
  if (!cli.existsSync()) return null;
  final offline = Directory('${Directory(macos).parent.path}/Resources/Offline');
  Map<String, dynamic>? manifest;
  try {
    manifest = (jsonDecode(File('${offline.path}/manifest.json').readAsStringSync()) as Map).cast<String, dynamic>();
  } catch (_) {}
  return _ArduinoCli(cli.path, offline.path, manifest);
}

class _ArduinoCli implements LocalBuilder {
  _ArduinoCli(this.cli, this.offline, this.manifest);
  final String cli, offline;

  /// The offline bundle's manifest.json ({arch, packs: {name: {file, version, boards}}}), or null.
  final Map<String, dynamic>? manifest;
  final _ready = <String>{};

  Map<String, dynamic> _pack(String name) => ((manifest?['packs'] as Map?)?[name] as Map?)?.cast<String, dynamic>() ?? const {};

  /// A board's tools come with the app, or (a developer's build) the Uno's can be fetched.
  @override
  bool canBuild(String board) {
    final b = _boards[board];
    if (b == null) return false;
    return manifest == null ? board == 'uno' : _pack(b.pack).isNotEmpty;
  }

  static final _home = Platform.environment['HOME'] ?? '';
  static final _support = '$_home/Library/Application Support/RoboCore';
  static final _data = '$_support/Arduino15';
  static final _caches = '$_home/Library/Caches/RoboCore';

  /// Only what arduino-cli needs, with RoboCore's own folders, so an installed Arduino IDE is never touched.
  Map<String, String> get _env => {
        'HOME': _home,
        'TMPDIR': Directory.systemTemp.path,
        'PATH': '/usr/bin:/bin',
        'LANG': 'C.UTF-8',
        'ARDUINO_DIRECTORIES_DATA': _data,
        'ARDUINO_DIRECTORIES_DOWNLOADS': '$_data/staging',
        'ARDUINO_DIRECTORIES_USER': '$_support/Arduino',
        'ARDUINO_BUILD_CACHE_PATH': '$_caches/arduino',
      };

  Future<ProcessResult> _run(List<String> args, {String? cwd}) =>
      Process.run(cli, args, environment: _env, includeParentEnvironment: false, workingDirectory: cwd);

  /// Runs arduino-cli and hands what it prints to [onLog]: download progress only at each tenth.
  Future<int> _stream(List<String> args, void Function(String line)? onLog) async {
    final p = await Process.start(cli, args, environment: _env, includeParentEnvironment: false);
    final shown = <String, int>{};
    void lines(Stream<List<int>> s) => s.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
          final t = l.split('\r').last.trim();
          if (t.isEmpty) return;
          final m = RegExp(r'^(\S+)\s+[\d.]+ \w+ / [\d.]+ \w+\s+([\d.]+)%').firstMatch(t);
          if (m != null) {
            final tenth = double.parse(m[2]!) ~/ 10;
            if ((shown[m[1]!] ?? -1) >= tenth) return;
            shown[m[1]!] = tenth;
          }
          onLog?.call(t);
        });
    lines(p.stdout);
    lines(p.stderr);
    return p.exitCode;
  }

  /// The board's tools: unpacked from the app the first time (no internet), or in a build without them, the Uno's
  /// fetched once. An error, or null.
  Future<String?> _ensure(({String fqbn, String pack, String core, String name, String chip, int bootloader, String flash}) b,
      void Function(String line)? onLog) async {
    if (_ready.contains(b.pack)) return null;
    if (manifest != null) {
      for (final name in ['base', b.pack]) {
        final err = await _unpack(name, b.name, onLog);
        if (err != null) return err;
      }
      _ready.add(b.pack);
      return null;
    }
    final list = await _run(['core', 'list', '--format', 'json']);
    if (list.exitCode == 0 && '${list.stdout}'.contains('"${b.core}"')) {
      _ready.add(b.pack);
      return null;
    }
    onLog?.call('Getting the ${b.name} tools, once (about 240 MB on this Mac). After this, compiling for it needs no internet.');
    if (await _stream(['core', 'update-index'], onLog) != 0 || await _stream(['core', 'install', b.core], onLog) != 0) {
      return 'Could not get the ${b.name} tools. Check the internet connection, then try again.';
    }
    _ready.add(b.pack);
    return null;
  }

  /// Unpacks an offline pack into Arduino15 unless that version is there already. A pack holds whole
  /// `packages/<vendor>` folders, so an older version is removed first.
  Future<String?> _unpack(String name, String board, void Function(String line)? onLog) async {
    final pack = _pack(name);
    final file = '$offline/${pack['file']}', version = '${pack['version']}';
    final marker = File('$_data/.robocore-$name');
    if (await marker.exists() && (await marker.readAsString()) == version) return null;
    if (!await File(file).exists()) return 'The ${name == 'base' ? 'compiler' : board} tools are missing from RoboCore. Install RoboCore again.';
    if (name != 'base') onLog?.call('Setting up the $board tools on this Mac, once. No internet needed: they came with RoboCore.');
    await Directory(_data).create(recursive: true);
    const owned = {'base': ['packages/builtin'], 'uno': ['packages/arduino'], 'esp32': ['packages/esp32']};
    for (final d in owned[name] ?? const <String>[]) {
      final old = Directory('$_data/$d');
      if (await old.exists()) await old.delete(recursive: true);
    }
    final r = await Process.run('/usr/bin/tar', ['-xf', file, '-C', _data]);
    if (r.exitCode != 0) return 'Could not set up the $board tools: ${'${r.stderr}'.trim()}';
    await marker.writeAsString(version);
    return null;
  }

  /// An Apple-silicon bundle can't run on an Intel Mac (an Intel one runs on Apple silicon, with Rosetta).
  String? _wrongMac() {
    final arch = manifest?['arch'];
    if (arch == 'arm64' && Abi.current() == Abi.macosX64) {
      return 'This RoboCore download is for Macs with Apple silicon, and this Mac has an Intel processor. '
          'Install the Intel version of RoboCore to compile here.';
    }
    return null;
  }

  @override
  Future<ServerBuild> compile({required String board, required List<SourceFile> files, void Function(String line)? onLog}) async {
    final b = _boards[board];
    if (b == null) return ServerBuild.failed('This Mac can’t build for $board yet.');
    final wrong = _wrongMac();
    if (wrong != null) return ServerBuild.failed(wrong);
    final started = DateTime.now();
    try {
      final missing = await _ensure(b, onLog);
      if (missing != null) return ServerBuild.failed(missing, retry: manifest == null);
    } catch (e) {
      return ServerBuild.failed('Could not run the compiler in RoboCore: $e');
    }

    // The sketch and its build stay between builds (one folder per board and sketch), so a rebuild only compiles
    // what changed: about 10 s less for an ESP32.
    final main = files.first.name;
    final name = main.replaceAll(RegExp(r'\.ino$'), '');
    final work = Directory('$_caches/build/$board-$name');
    final sketch = Directory('${work.path}/$name');
    final build = Directory('${work.path}/build');
    try {
      await sketch.create(recursive: true);
      await build.create(recursive: true);
      final names = [for (final f in files) f.name];
      await for (final e in sketch.list()) {
        if (e is File && !names.contains(e.uri.pathSegments.last)) await e.delete(); // a tab deleted since last time
      }
      for (final f in files) {
        final file = File('${sketch.path}/${f.name}');
        if (!await file.exists() || await file.readAsString() != f.content) await file.writeAsString(f.content);
      }
      final libraries = Directory('$offline/libraries');
      final r = await _run([
        'compile', '--fqbn', b.fqbn, '--build-path', build.path, '--warnings', 'default', '--format', 'json',
        if (await libraries.exists()) ...['--libraries', libraries.path],
        sketch.path,
      ], cwd: work.path);
      final result = parseCliJson('${r.stdout}');
      if (result == null) {
        final said = '${r.stderr}${r.stdout}'.trim();
        return ServerBuild.failed('The compiler gave no result${said.isEmpty ? '' : ': ${said.split('\n').last}'}');
      }
      String clean(Object? t) => '${t ?? ''}'
          .replaceAll('${sketch.path}/', '')
          .replaceAll(sketch.path, name)
          .replaceAll(work.path, '')
          .replaceAll(_data, '<arduino>')
          .replaceAll(offline, '<RoboCore>');
      final out = clean(result['compiler_out']), err = clean(result['compiler_err']);
      var problems = mergeProblems(
        parseStructured((result['builder_result'] as Map?)?['diagnostics'], sketch.path, names),
        parseDiagnostics('$err\n$out', names),
      )..sort((a, b) => (a['severity'] == b['severity'] ? 0 : (a['severity'] == 'error' ? -1 : 1)));
      final log = '$out${err.isEmpty ? '' : '\n$err'}'.trim();
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (result['success'] != true) {
        final error = clean(result['error'] ?? 'Compilation failed.');
        if (error.contains('bad CPU type')) {
          return ServerBuild.failed('The ${b.name} compiler is made for Intel Macs, and this Mac needs Apple’s Rosetta to '
              'run it. Connect to the internet once, then open Terminal and type: softwareupdate --install-rosetta');
        }
        if (!problems.any((p) => p['severity'] == 'error')) {
          problems = [
            {'severity': 'error', 'file': main, 'line': 1, 'message': error},
            ...problems,
          ];
        }
        return ServerBuild.fromJson({'ok': false, 'problems': problems, 'log': log, 'elapsedMs': ms}, mainFile: main);
      }
      return ServerBuild.fromJson({
        'ok': true,
        'problems': problems,
        'sizes': parseSizes(result, out),
        'log': log,
        'image': b.chip.isEmpty ? {'format': 'hex', 'data': await File('${build.path}/$main.hex').readAsString()} : await _esp32Image(b, build.path, main),
        'elapsedMs': ms,
      }, mainFile: main);
    } catch (e) {
      return ServerBuild.failed('Compiling on this Mac failed: $e');
    }
  }

  /// The four parts of an ESP32 program and where each goes in flash (the core's merge-bin layout).
  Future<Map<String, dynamic>> _esp32Image(
      ({String fqbn, String pack, String core, String name, String chip, int bootloader, String flash}) b, String build, String main) async {
    final cores = Directory('$_data/packages/esp32/hardware/esp32');
    final version = (await cores.list().map((e) => e.path).toList()..sort()).last;
    final parts = [
      ('bootloader', b.bootloader, '$build/$main.bootloader.bin'),
      ('partitions', 0x8000, '$build/$main.partitions.bin'),
      ('boot_app0', 0xe000, '$version/tools/partitions/boot_app0.bin'),
      ('app', 0x10000, '$build/$main.bin'),
    ];
    return {
      'format': 'esp32',
      'chip': b.chip,
      'flashSize': b.flash,
      'parts': [
        for (final (name, offset, path) in parts)
          await File(path).readAsBytes().then((d) => {'name': name, 'offset': offset, 'size': d.length, 'data': base64Encode(d)}),
      ],
    };
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
