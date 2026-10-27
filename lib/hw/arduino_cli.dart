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

  /// Installs the core for [board] once: arduino:avr for the Uno, the esp32 core for the others.
  Future<void> ensureCore(String board, LogFn log) {
    final core = board == 'uno' ? kAvrCore : kEsp32Core;
    return _coresReady[core] ??= _installCore(core, log).catchError((Object e) {
      _coresReady.remove(core);
      throw e;
    });
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
