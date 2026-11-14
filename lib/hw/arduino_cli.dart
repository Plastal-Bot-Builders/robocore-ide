// arduino-cli on this computer, for the Windows app: real compiles (local_compiler_windows.dart) and the board tools
// that write them over USB (usb_link_native.dart). The same arduino-cli, cores and libraries as the compile
// server (server/Dockerfile).
//
// The first time it is needed the app downloads arduino-cli (checked against Arduino's published checksum) into
// %LOCALAPPDATA%\RoboCore, then installs the board's core and the IDE's libraries. They go where the Arduino IDE
// keeps them (%LOCALAPPDATA%\Arduino15, Documents\Arduino\libraries), so a PC with the Arduino IDE shares them.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const kCliVersion = '1.5.1';
const kEsp32Core = 'esp32:esp32@3.3.12';
const kAvrCore = 'arduino:avr';
const kEsp32Index = 'https://espressif.github.io/arduino-esp32/package_esp32_index.json';
const kLibraries = ['ESP32Servo@3.2.1', 'Adafruit NeoPixel@1.12.3', 'NewPing@1.9.7', 'LiquidCrystal I2C@1.1.2'];

/// FQBN per board id (lib/data/catalog.dart), as in server/src/boards.js.
const kFqbn = {
  'v2': 'esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=enabled,CPUFreq=240',
  'devkit': 'esp32:esp32:esp32:FlashSize=4M,PartitionScheme=default',
  'nodemcu': 'esp32:esp32:nodemcu-32s',
  'uno': 'arduino:avr:uno',
};

/// Where each part of an ESP32 build goes in flash (server/src/boards.js ESP32_PARTS).
List<(String, int)> esp32Parts(String board) => [
      ('bootloader', board == 'v2' ? 0x0 : 0x1000),
      ('partitions', 0x8000),
      ('boot_app0', 0xe000),
      ('app', 0x10000),
    ];

typedef LogFn = void Function(String line);

/// Files an ESP32 build for [board] needs from the esp32 package under [dataDir] (Arduino15). Returns the ones that
/// are missing, as paths under packages\esp32. An empty list means the install looks complete.
///
/// An interrupted download or unpack (a dropped connection, an antivirus holding a file, a full disk) leaves arduino-cli
/// believing the core is installed while files are gone; the first compile then fails with "No such file or
/// directory". [sep] is the path separator (the tests run on Linux).
List<String> missingEsp32Files(String dataDir, String board, {String version = '3.3.12', String? sep, bool windows = true}) {
  final s = sep ?? Platform.pathSeparator;
  String j(List<String> parts) => parts.join(s);
  final pkg = j([dataDir, 'packages', 'esp32']);
  final chip = board == 'v2' ? 'esp32s3' : 'esp32';
  final exe = windows ? '.exe' : '';
  final missing = <String>[];

  void file(List<String> rel) {
    if (!File(j([pkg, ...rel])).existsSync()) missing.add(j(rel));
  }

  /// [rel] under any installed version of tool [tool].
  void toolFile(String tool, List<String> rel) {
    final d = Directory(j([pkg, 'tools', tool]));
    final ok = d.existsSync() &&
        d.listSync().whereType<Directory>().any((v) => File(j([v.path, ...rel])).existsSync());
    if (!ok) missing.add(j(['tools', tool, '<version>', ...rel]));
  }

  file(['hardware', 'esp32', version, 'platform.txt']);
  file(['hardware', 'esp32', version, 'boards.txt']);
  file(['hardware', 'esp32', version, 'cores', 'esp32', 'Arduino.h']);
  file(['hardware', 'esp32', version, 'tools', 'partitions', 'boot_app0.bin']);
  toolFile('$chip-libs', ['include', 'esp_common', 'include', 'esp_attr.h']);
  toolFile('$chip-libs', ['flags', 'defines']);
  toolFile('xtensa-esp-elf-gcc', ['bin', 'xtensa-$chip-elf-g++$exe']);
  toolFile('esptool_py', ['esptool$exe']);
  return missing;
}

/// True when [compilerText] says a file of the esp32 package itself is missing (a broken install, not a sketch problem):
/// a line that both points into packages/esp32 and says the file or program isn't there. A sketch that includes a
/// header it doesn't have fails on its own file, so it is not mistaken for this.
bool isBrokenEsp32Install(String compilerText) {
  final missing = RegExp(
      r'No such file or directory|file does not exist|cannot find the (file|path)|not recognized as an internal or external command',
      caseSensitive: false);
  for (final line in compilerText.split(RegExp(r'\r?\n'))) {
    final t = line.replaceAll('\\', '/');
    if (missing.hasMatch(t) && t.toLowerCase().contains('packages/esp32/')) return true;
  }
  return false;
}

class CliError implements Exception {
  CliError(this.message);
  final String message;
  @override
  String toString() => message;
}

class ArduinoCli {
  ArduinoCli._();
  static final instance = ArduinoCli._();

  /// Windows only, and not while the tests run (they use fakes).
  bool get supported => Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST');

  String get _localAppData => Platform.environment['LOCALAPPDATA'] ?? '${Platform.environment['USERPROFILE']}\\AppData\\Local';
  String get home => '$_localAppData\\RoboCore';
  String get exe => '$home\\arduino-cli\\arduino-cli.exe';

  /// Arduino's data folder (cores and their tools).
  String get dataDir => '$_localAppData\\Arduino15';

  /// The RoboCore library, copied next to RoboCore.exe (windows/CMakeLists.txt).
  String get libraryDir => '${File(Platform.resolvedExecutable).parent.path}\\data\\firmware\\RoboCore';

  Future<void>? _cliReady;
  final _coresReady = <String, Future<void>>{};
  Future<void>? _libsReady;

  /// Downloads arduino-cli once.
  Future<void> ensureCli(LogFn log) {
    if (File(exe).existsSync()) return Future.value();
    return _cliReady ??= _downloadCli(log).whenComplete(() => _cliReady = null);
  }

  Future<void> _downloadCli(LogFn log) async {
    final name = 'arduino-cli_${kCliVersion}_Windows_64bit.zip';
    log('First time on this computer: downloading arduino-cli $kCliVersion (the Arduino compiler, about 30 MB)…');
    final dir = Directory('$home\\arduino-cli');
    await dir.create(recursive: true);
    final zip = File('$home\\$name');
    try {
      // Arduino's download site, or the same files on GitHub when that site can't be reached.
      String? sums;
      CliError? last;
      for (final base in const [
        'https://downloads.arduino.cc/arduino-cli',
        'https://github.com/arduino/arduino-cli/releases/download/v$kCliVersion',
      ]) {
        try {
          await _download('$base/$name', zip);
          sums = await _getText('$base/$kCliVersion-checksums.txt');
          break;
        } on CliError catch (e) {
          last = e;
        }
      }
      if (sums == null) throw last ?? CliError('Could not download arduino-cli.');
      final want = RegExp('^([0-9a-f]{64})\\s+${RegExp.escape(name)}\$', multiLine: true).firstMatch(sums)?.group(1);
      final got = await _sha256(zip);
      if (want == null || got != want) throw CliError('The arduino-cli download did not match its checksum. Try again.');
      // Windows' own tar (bsdtar) unpacks zip files.
      final tar = '${Platform.environment['SystemRoot'] ?? 'C:\\Windows'}\\System32\\tar.exe';
      final r = await Process.run(tar, ['-xf', zip.path, '-C', dir.path]);
      if (r.exitCode != 0 || !File(exe).existsSync()) throw CliError('Could not unpack arduino-cli: ${r.stderr}');
      log('arduino-cli $kCliVersion is ready.');
    } finally {
      if (zip.existsSync()) await zip.delete();
    }
  }

  /// Downloads [url] to [to]. A dropped connection carries on from where it stopped (HTTP Range), so a slow or
  /// unreliable connection still gets there.
  Future<void> _download(String url, File to) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    if (to.existsSync()) await to.delete();
    int? total;
    try {
      for (var attempt = 1;; attempt++) {
        final have = to.existsSync() ? to.lengthSync() : 0;
        if (total != null && have >= total) return;
        try {
          final req = await client.getUrl(Uri.parse(url));
          if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
          final res = await req.close();
          if (res.statusCode == 404) throw CliError('Download failed (not found): $url');
          if (res.statusCode != 200 && res.statusCode != 206) throw HttpException('HTTP ${res.statusCode}');
          final resumed = res.statusCode == 206;
          if (res.contentLength >= 0) total = (resumed ? have : 0) + res.contentLength;
          final sink = to.openWrite(mode: resumed ? FileMode.append : FileMode.write);
          try {
            await res.timeout(const Duration(seconds: 60)).forEach(sink.add);
          } finally {
            await sink.close();
          }
          if (total == null || to.lengthSync() >= total) return;
          throw const HttpException('connection closed early');
        } on CliError {
          rethrow;
        } catch (e) {
          if (attempt >= 30) throw CliError('Could not download $url. Check the internet connection and try again. ($e)');
          await Future<void>.delayed(Duration(seconds: attempt < 5 ? 2 : 5));
        }
      }
    } finally {
      client.close();
    }
  }

  Future<String> _getText(String url) async {
    final f = File('$home\\download.tmp');
    try {
      await _download(url, f);
      return await f.readAsString();
    } finally {
      if (f.existsSync()) await f.delete();
    }
  }

  Future<String> _sha256(File f) async {
    final r = await Process.run('certutil', ['-hashfile', f.path, 'SHA256']);
    final m = RegExp(r'^([0-9a-fA-F ]{64,})$', multiLine: true).firstMatch('${r.stdout}');
    return (m?.group(1) ?? '').replaceAll(' ', '').toLowerCase();
  }

  /// Installs the core for [board] once: arduino:avr for the Uno, the esp32 core for the others. For the esp32 core it
  /// then checks that the files a build needs are really there, and repairs the install if not (see [repairEsp32]).
  Future<void> ensureCore(String board, LogFn log) async {
    final core = board == 'uno' ? kAvrCore : kEsp32Core;
    await _install(core, log);
    if (core != kEsp32Core) return;
    final missing = missingEsp32Files(dataDir, board, version: kEsp32Core.split('@').last);
    if (missing.isEmpty) return;
    await repairEsp32(board, log, missing: missing);
  }

  Future<void> _install(String core, LogFn log) => _coresReady[core] ??= _installCore(core, log).catchError((Object e) {
        _coresReady.remove(core);
        throw e;
      });

  /// Deletes a broken esp32 package (and the downloads arduino-cli staged for it, which may be the cut-off ones) and
  /// installs it again. Throws [CliError] if files are still missing afterwards.
  Future<void> repairEsp32(String board, LogFn log, {List<String>? missing}) async {
    final gone = missing ?? missingEsp32Files(dataDir, board, version: kEsp32Core.split('@').last);
    log('The ESP32 board files on this computer are incomplete'
        '${gone.isEmpty ? '' : ' (missing ${gone.first}${gone.length > 1 ? ' and ${gone.length - 1} more' : ''})'}. '
        'Removing them and installing them again…');
    _coresReady.remove(kEsp32Core);
    final failed = <String>[];
    Future<void> remove(FileSystemEntity e) async {
      try {
        if (e.existsSync()) await e.delete(recursive: true);
      } catch (_) {
        failed.add(e.path);
      }
    }

    await remove(Directory('$dataDir\packages\esp32'));
    // arduino-cli keeps each download in staging and reuses it; a cut-off one would be unpacked broken again.
    final staging = Directory('$dataDir\staging\packages');
    if (staging.existsSync()) {
      final esp = RegExp(r'esp32|esp-|xtensa|riscv32|esptool|mklittlefs|mkspiffs|openocd|-libs-', caseSensitive: false);
      for (final f in staging.listSync().whereType<File>()) {
        if (esp.hasMatch(f.uri.pathSegments.last)) await remove(f);
      }
    }
    if (failed.isNotEmpty) {
      throw CliError('Could not remove the broken ESP32 board files (${failed.first}). Close the Arduino IDE and any '
          'other app using them, then try again.');
    }
    await _install(kEsp32Core, log);
    final still = missingEsp32Files(dataDir, board, version: kEsp32Core.split('@').last);
    if (still.isNotEmpty) {
      throw CliError('The ESP32 board files are still incomplete after reinstalling (missing ${still.first}). An '
          'antivirus may be removing files from %LOCALAPPDATA%\\Arduino15; allow that folder, then try again.');
    }
    log('ESP32 board files repaired.');
  }

  Future<void> _installCore(String core, LogFn log) async {
    final id = core.split('@').first;
    final version = core.contains('@') ? core.split('@').last : null;
    final list = await run(['core', 'list', '--format', 'json']);
    final installed = _installedCores('${list.stdout}');
    if (installed.containsKey(id) && (version == null || installed[id] == version)) return;
    final esp = id.startsWith('esp32');
    log(esp
        ? 'Installing the ESP32 board files ($core). This happens once and downloads about 600 MB, so it takes a few minutes…'
        : 'Installing the Arduino Uno board files ($id). This happens once and takes a minute…');
    await stream(['core', 'update-index'], log);
    await stream(['core', 'install', core], log, failure: 'Could not install $core.');
    log('Board files installed.');
  }

  Map<String, String> _installedCores(String json) {
    final out = <String, String>{};
    try {
      final j = jsonDecode(json);
      final list = j is Map ? (j['platforms'] as List? ?? const []) : (j as List);
      for (final p in list) {
        if (p is! Map) continue;
        final id = '${p['id'] ?? ''}';
        final v = p['installed_version'] ?? p['installed'];
        if (id.isNotEmpty && v != null) out[id] = '$v';
      }
    } catch (_) {}
    return out;
  }

  /// Installs the optional libraries the IDE lists (Libraries page) once.
  Future<void> ensureLibraries(LogFn log) {
    final mark = File('$home\\libraries-$kCliVersion.done');
    if (mark.existsSync()) return Future.value();
    return _libsReady ??= () async {
      log('Installing the Arduino libraries (Servo, NeoPixel, NewPing, LiquidCrystal I2C)…');
      await stream(['lib', 'update-index'], log);
      await stream(['lib', 'install', ...kLibraries], log, failure: 'Could not install the Arduino libraries.');
      await mark.writeAsString('ok');
    }()
        .whenComplete(() => _libsReady = null);
  }

  /// Everything a build for [board] needs.
  Future<void> ensureAll(String board, LogFn log) async {
    await ensureCli(log);
    await ensureCore(board, log);
    try {
      await ensureLibraries(log);
    } on CliError catch (e) {
      // Only sketches that use one of them need these; the rest still compile. The next build tries again.
      log('${e.message} Sketches that use these libraries won’t compile until they install.');
    }
  }

  List<String> get _common => ['--additional-urls', kEsp32Index];

  /// Added to this computer's environment. Otherwise arduino-cli asks downloads.arduino.cc once a day whether there is
  /// a newer arduino-cli (the Mac app turns it off the same way, in local_compiler_native.dart).
  static const _env = {'ARDUINO_UPDATER_ENABLE_NOTIFICATION': 'false'};

  Future<ProcessResult> run(List<String> args, {String? workingDirectory}) => Process.run(exe, [...args, ..._common],
      workingDirectory: workingDirectory, environment: _env, stdoutEncoding: utf8, stderrEncoding: utf8);

  Future<Process> start(List<String> args) => Process.start(exe, [...args, ..._common], environment: _env);

  /// Runs arduino-cli, passing each output line to [log]. Throws [CliError] with [failure] when it fails.
  Future<void> stream(List<String> args, LogFn log, {String? failure}) async {
    final p = await start(args);
    final tail = <String>[];
    void line(String l) {
      final t = l.trimRight();
      if (t.isEmpty) return;
      tail.add(t);
      if (tail.length > 8) tail.removeAt(0);
      // Download progress bars redraw one line many times; show only finished steps.
      if (!t.contains('%') || t.contains('100')) log(t);
    }

    final a = p.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(line);
    final b = p.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(line);
    final code = await p.exitCode;
    await a.catchError((_) {});
    await b.catchError((_) {});
    if (code != 0 && failure != null) throw CliError('$failure ${tail.join(' ')}'.trim());
  }

  /// A tool from an installed core, for example ('arduino', 'avrdude', 'bin\\avrdude.exe'); the newest version.
  String? tool(String packager, String name, String file) {
    final d = Directory('$dataDir\\packages\\$packager\\tools\\$name');
    if (!d.existsSync()) return null;
    final versions = d.listSync().whereType<Directory>().map((e) => e.path).toList()..sort();
    for (final v in versions.reversed) {
      final f = File('$v\\$file');
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  /// The esp32 core's boot_app0.bin.
  String? bootApp0() {
    final d = Directory('$dataDir\\packages\\esp32\\hardware\\esp32');
    if (!d.existsSync()) return null;
    final versions = d.listSync().whereType<Directory>().map((e) => e.path).toList()..sort();
    for (final v in versions.reversed) {
      final f = File('$v\\tools\\partitions\\boot_app0.bin');
      if (f.existsSync()) return f.path;
    }
    return null;
  }
}

/// Ends [pid] and the processes it started (arduino-cli monitor runs a serial-monitor.exe that holds the port).
Future<void> killTree(int pid) async {
  try {
    await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
  } catch (_) {}
}
