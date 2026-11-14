// USB link for the Windows app: the board's COM port through the same tools the Arduino IDE uses.
//  - Ports: `arduino-cli board list`. Connect picks the USB serial port with a board on it.
//  - Serial Monitor: `arduino-cli monitor` (text in on stdin, out on stdout).
//  - Upload: avrdude through `arduino-cli upload` for an Uno (its Optiboot bootloader), the esp32 core's esptool for
//    an ESP32 (parts at their flash offsets). The monitor is closed while it runs, then reopened.
//  - Test connection: the chip's own answer (avrdude reads the ATmega's signature; esptool asks the ESP32 its type).
//  - A board that keeps restarting (a brand-new empty ESP32-S3, or a crashing sketch) is reported once ('bootloop'),
//    not as an unplug and replug every second, and its port stays selected. Upload and Test connection keep retrying
//    esptool for up to 20 s, catching the board the moment it comes back, so no BOOT or RESET button is needed.
// usb_link_native.dart hands it out on Windows; in the tests it reports itself unsupported.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'arduino_cli.dart';
import 'boot_loop.dart';
import 'usb_link.dart';

/// How long Upload and Test connection keep trying to catch a restarting ESP32.
const kCatchWindow = Duration(seconds: 20);

/// esptool output that means the board went away or did not answer: worth another try while it restarts.
final _retryable = RegExp(
    r'Failed to connect|No serial data received|Wrong boot mode|could not open port|FileNotFoundError|PermissionError|'
    r'cannot find the file|ClearCommError|SerialException|device reports readiness|Write timeout|'
    r'device disconnected|Errno 2|Access is denied|port is busy|Invalid head of packet|Timed out waiting',
    caseSensitive: false);

/// USB vendor ids of boards and USB-serial chips the IDE knows.
const _knownVids = {
  '0x2341': 'Arduino',
  '0x2a03': 'Arduino',
  '0x1a86': 'CH340',
  '0x0403': 'FTDI',
  '0x10c4': 'CP210x',
  '0x303a': 'Espressif',
};
const _espressifVids = {'0x303a', '0x10c4', '0x1a86'};

class _Port {
  _Port(this.address, this.label, this.vid, this.pid, this.boardName);
  final String address, label, vid, pid;
  final String? boardName;

  String get display => [address, boardName ?? _knownVids[vid]].whereType<String>().join(' · ');
}

class _NativeUsb extends UsbLink {
  _NativeUsb() {
    if (_cli.supported) _detect = Timer.periodic(const Duration(milliseconds: 1500), (_) => _lookForBoards());
  }

  final _cli = ArduinoCli.instance;

  // Auto-detect, as the Arduino IDE and the LEGO app do: the COM ports are checked all the time (a fast registry
  // read), and a board that appears (or is already there when the app starts) is reported once as 'found', so the
  // app can connect without anyone pressing Connect.
  Timer? _detect;
  Set<String> _seen = const {};
  final _offered = <String>{};
  bool _looking = false, _opening = false;

  Future<void> _lookForBoards() async {
    if (_looking || _opening || _busy || _job != null) return;
    _looking = true;
    try {
      final now = await _comPorts();
      _offered.removeWhere((a) => !now.contains(a)); // gone: report it again when it comes back
      final fresh = now.difference(_seen);
      _seen = now;
      // Nothing new, or a board is already in use (or the selected one is being waited for after a restart).
      if (fresh.isEmpty || _monitor != null || (_watch?.isActive ?? false)) return;
      final p = _pick(await _ports(), espressifOnly: true);
      if (p == null) return;
      final a = p.address.toUpperCase();
      if (!fresh.contains(a) || !_offered.add(a)) return;
      onEvent?.call('found', jsonEncode({'label': p.display, 'address': p.address}));
    } catch (_) {
      // arduino-cli not ready yet, or the registry read failed: try again on the next tick
    } finally {
      _looking = false;
    }
  }

  @override
  bool get supported => _cli.supported;

  @override
  bool get isOpen => _monitor != null;

  _Port? _port;
  int _baud = 115200;
  Process? _monitor;
  bool _closing = false;
  Process? _job; // a running upload or identify
  bool _cancel = false, _wrote = false;
  Timer? _watch;

  // Restart loops (boot_loop.dart): one 'bootloop' event per loop, no unplug notice for a port that comes straight back.
  final _loop = BootLoopDetector();
  bool _loopAnnounced = false;
  bool _unplugAnnounced = false;
  bool _starting = false; // opening the monitor: its first exit is a retry, not an unplug
  bool _busy = false; // flashing or identifying: the replug watcher leaves the port alone
  Timer? _unplugNotice, _settle;

  void _log(String line) => onEvent?.call('log', line);

  // ---------- ports ----------

  Future<List<_Port>> _ports() async {
    await _cli.ensureCli(_log);
    final r = await _cli.run(['board', 'list', '--format', 'json']);
    final out = <_Port>[];
    try {
      final j = jsonDecode('${r.stdout}');
      final list = j is Map ? (j['detected_ports'] as List? ?? const []) : (j as List);
      for (final d in list) {
        if (d is! Map) continue;
        final p = d['port'] is Map ? d['port'] as Map : d;
        if ('${p['protocol'] ?? ''}' != 'serial') continue;
        final props = (p['properties'] as Map?) ?? const {};
        final vid = '${props['vid'] ?? ''}'.toLowerCase(), pid = '${props['pid'] ?? ''}'.toLowerCase();
        if (vid.isEmpty) continue; // Bluetooth and built-in COM ports have no USB ids
        final boards = d['matching_boards'] as List?;
        final name = boards != null && boards.isNotEmpty && boards.first is Map ? '${(boards.first as Map)['name']}' : null;
        out.add(_Port('${p['address']}', '${p['label'] ?? p['address']}', vid, pid, name));
      }
    } catch (_) {}
    return out;
  }

  /// The board's port: a board arduino-cli recognises, else a known board USB chip. Never another USB device (a PC's
  /// own modem or Bluetooth ports show up as USB serial ports too).
  _Port? _pick(List<_Port> ports, {bool espressifOnly = false}) {
    final boards = [for (final p in ports) if (p.boardName != null || _knownVids.containsKey(p.vid)) p];
    if (boards.isEmpty) return null;
    if (_port != null) {
      for (final p in boards) {
        if (p.address == _port!.address) return p;
      }
    }
    final pool = espressifOnly && boards.any((p) => _espressifVids.contains(p.vid))
        ? boards.where((p) => _espressifVids.contains(p.vid)).toList()
        : boards;
    return pool.firstWhere((p) => p.boardName != null, orElse: () => pool.first);
  }

  Future<UsbResult> _open({required int baud, bool espressifOnly = false, bool quiet = false}) async {
    if (!supported) return UsbResult.unsupported;
    _opening = true;
    try {
      final port = _pick(await _ports(), espressifOnly: espressifOnly) ?? await _catchPort(espressifOnly: espressifOnly);
      if (port == null) {
        return const UsbResult(false,
            code: 'no-port', message: 'No board found on USB. Plug it in with a data USB cable (some cables only charge) and press Connect.');
      }
      _port = port;
      _baud = baud;
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        try {
          await _startMonitor();
          break;
        } on CliError {
          // A board in a restart loop drops its port every second or so. Keep it selected and let the watcher catch it.
          if (_loop.looping) {
            _watchForReplug();
            break;
          }
          if (DateTime.now().isAfter(end)) rethrow;
          await _waitPresent(port.address, end.difference(DateTime.now()));
        }
      }
      return UsbResult(true, data: {'label': port.display});
    } on CliError catch (e) {
      return UsbResult(false, code: 'helper', message: e.message);
    } catch (e) {
      return UsbResult(false, code: 'helper', message: 'Could not open the board’s port: $e');
    } finally {
      _opening = false;
      _seen = await _comPorts(); // ports seen while opening are not news to the auto-detect
    }
  }

  /// No board in one scan: a board restarting in a loop is only on USB for moments at a time, so watch the COM ports
  /// for a few seconds. A port that comes up is checked with arduino-cli; one that keeps coming and going is a
  /// restarting board (counted as drops, so the restart-loop message appears) and is used even unidentified.
  Future<_Port?> _catchPort({bool espressifOnly = false, Duration limit = const Duration(seconds: 8)}) async {
    final end = DateTime.now().add(limit);
    var last = await _comPorts();
    final flips = <String, int>{};
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final now = await _comPorts();
      for (final a in {...last, ...now}) {
        if (last.contains(a) != now.contains(a)) flips[a] = (flips[a] ?? 0) + 1;
      }
      final appeared = now.difference(last);
      last = now;
      if (appeared.isNotEmpty) {
        final p = _pick(await _ports(), espressifOnly: espressifOnly);
        if (p != null) return p;
      }
      for (final e in flips.entries) {
        if (e.value >= 3) {
          // Up, down, up again within seconds: the board keeps restarting.
          final port = _Port(e.key, e.key, '0x303a', '', null);
          _port = port;
          for (var i = 0; i < e.value ~/ 2; i++) {
            _loop.onDrop();
          }
          if (_loop.looping) _announceLoop(_loop.reason);
          return port;
        }
      }
    }
    return null;
  }

  // ---------- Serial Monitor ----------

  Future<void> _startMonitor() async {
    await _stopMonitor();
    final port = _port!;
    final p = await _cli.start(['monitor', '-p', port.address, '--config', 'baudrate=$_baud', '--quiet']);
    _monitor = p;
    _closing = false;
    p.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((t) {
      final r = _loop.onText(t);
      if (r != null) _announceLoop(r);
      onText?.call(t);
    });
    p.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((t) {
      final s = t.trim();
      if (s.isNotEmpty) onEvent?.call('log', s);
    });
    unawaited(p.exitCode.then((code) {
      if (!identical(_monitor, p)) return;
      _monitor = null;
      if (_closing) return;
      // The monitor ended by itself: the board restarted (its USB port drops with the chip), was unplugged, or another
      // app took the port. Count it, and only call it an unplug if the port stays away.
      final r = _loop.onDrop();
      if (r != null) _announceLoop(r);
      if (_starting) return; // _startMonitor reports it
      _scheduleUnplugNotice(port);
      _watchForReplug();
    }));
    // A port that can't be opened ends the monitor straight away.
    _starting = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } finally {
      _starting = false;
    }
    if (!identical(_monitor, p)) {
      throw CliError('Could not open ${port.address}. Close other apps that use it (the Arduino IDE’s Serial Monitor, for example) and try again.');
    }
  }

  /// "Unplugged" only once the port has been gone for a few seconds and it isn't a restart loop.
  void _scheduleUnplugNotice(_Port port) {
    _unplugNotice?.cancel();
    if (_loop.looping) return;
    _unplugNotice = Timer(const Duration(seconds: 3), () {
      if (_monitor != null || _busy || _loop.looping) return;
      _unplugAnnounced = true;
      onEvent?.call('unplugged', port.display);
    });
  }

  void _announceLoop(BootLoopReason reason) {
    _unplugNotice?.cancel();
    if (_loopAnnounced) return;
    _loopAnnounced = true;
    onEvent?.call('bootloop', jsonEncode({'reason': reason.name, 'label': _port?.display ?? 'USB board'}));
    _settle?.cancel();
    _settle = Timer.periodic(const Duration(seconds: 2), (t) {
      if (!_loopAnnounced) return t.cancel();
      if (_loop.settle()) {
        t.cancel();
        _loopAnnounced = false;
        onEvent?.call('bootloop-ended', _port?.display ?? 'USB board');
      }
    });
  }

  void _clearLoop() {
    _loop.reset();
    _loopAnnounced = false;
    _settle?.cancel();
  }

  // ---------- is the port there? ----------

  /// The COM ports Windows has right now (fast: a registry read, not a USB scan).
  Future<Set<String>> _comPorts() async {
    try {
      final r = await Process.run('reg', ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM']);
      return {for (final m in RegExp(r'\b(COM\d+)\b').allMatches('${r.stdout}')) m.group(1)!.toUpperCase()};
    } catch (_) {
      return {for (final p in await _ports()) p.address.toUpperCase()};
    }
  }

  Future<bool> _present(String address) async => (await _comPorts()).contains(address.toUpperCase());

  /// Waits (up to [limit]) for [address] to be back; true as soon as it is.
  Future<bool> _waitPresent(String address, Duration limit) async {
    final end = DateTime.now().add(limit);
    while (true) {
      if (_cancel) return false;
      if (await _present(address)) return true;
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  /// Reopens the Serial Monitor on the board's port, giving a restarting board up to [limit] to come back.
  Future<bool> _reopen(Duration limit) async {
    final port = _port;
    if (port == null) return false;
    final end = DateTime.now().add(limit);
    while (true) {
      if (await _waitPresent(port.address, end.difference(DateTime.now()))) {
        try {
          await _startMonitor();
          return true;
        } catch (_) {}
      }
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _stopMonitor() async {
    final p = _monitor;
    if (p == null) return;
    _closing = true;
    _monitor = null;
    await killTree(p.pid);
    await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
    // Windows frees the COM port a moment after the process ends.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  /// Watches for the board's port to come back and reopens the monitor. The selected port is kept: a restarting board
  /// comes back on the same COM port, and another board plugged in meanwhile is not taken instead.
  void _watchForReplug() {
    _watch?.cancel();
    var checking = false;
    _watch = Timer.periodic(const Duration(milliseconds: 400), (t) async {
      if (_monitor != null || _job != null) return t.cancel();
      if (checking || _busy) return;
      checking = true;
      try {
        final port = _port;
        if (port == null) return t.cancel();
        if (!await _present(port.address) || _monitor != null || _busy) return;
        try {
          await _startMonitor();
        } catch (_) {
          return; // it dropped again straight away (still restarting): keep watching
        }
        t.cancel();
        _unplugNotice?.cancel();
        if (_unplugAnnounced && !_loop.looping) onEvent?.call('reconnected', port.display);
        _unplugAnnounced = false;
      } finally {
        checking = false;
      }
    });
  }

  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) {
    _port = null;
    _clearLoop();
    _unplugAnnounced = false;
    return _open(baud: baud, espressifOnly: espressifOnly);
  }

  @override
  Future<UsbResult> reconnect({required int baud}) async {
    if (_monitor != null) return UsbResult(true, data: {'label': _port?.display ?? 'USB board'});
    return _open(baud: baud, quiet: true);
  }

  @override
  Future<UsbResult> disconnect() async {
    _watch?.cancel();
    _unplugNotice?.cancel();
    _clearLoop();
    await _stopMonitor();
    return const UsbResult(true);
  }

  @override
  Future<UsbResult> setBaud(int baud) async {
    _baud = baud;
    if (_monitor == null) return const UsbResult(true);
    try {
      await _startMonitor();
      return const UsbResult(true);
    } catch (e) {
      return UsbResult(false, code: 'helper', message: '$e');
    }
  }

  @override
  Future<UsbResult> write(String text) async {
    final p = _monitor;
    if (p == null) return const UsbResult(false, code: 'closed', message: 'The board is not connected.');
    try {
      p.stdin.add(utf8.encode(text));
      await p.stdin.flush();
      return const UsbResult(true);
    } catch (e) {
      return UsbResult(false, code: 'write', message: 'Could not send to the board: $e');
    }
  }

  /// Opening the port restarts an Uno (DTR) and an ESP32 on its USB port, so reopening the monitor resets the board.
  @override
  Future<UsbResult> reset({String arch = 'esp32'}) async {
    if (_port == null) return const UsbResult(false, code: 'closed', message: 'The board is not connected.');
    try {
      await _startMonitor();
      onEvent?.call('restarted', '');
      return const UsbResult(true);
    } catch (e) {
      return UsbResult(false, code: 'helper', message: '$e');
    }
  }

  // ---------- upload ----------

  /// The board's port for an upload or test. A board in a restart loop can be off USB at this very moment, so the
  /// selected port gets up to [kCatchWindow] to come back before the answer is "no board".
  Future<_Port?> _portForJob() async {
    _cancel = false;
    final port = _pick(await _ports());
    if (port != null) return port;
    final selected = _port;
    if (selected != null && await _waitPresent(selected.address, kCatchWindow)) return selected;
    return null;
  }

  @override
  Future<UsbResult> flash(Map<String, dynamic> job) async {
    if (!supported) return UsbResult.unsupported;
    final wasOpen = _monitor != null || _loopAnnounced;
    _busy = true;
    _watch?.cancel();
    _unplugNotice?.cancel();
    try {
      final port = await _portForJob();
      if (port == null) {
        return const UsbResult(false, code: 'no-port', message: 'No board found on USB. Plug it in with a data USB cable and try again.');
      }
      _port = port;
      if (job['monitorBaud'] is num) _baud = (job['monitorBaud'] as num).toInt();
      _wrote = false;
      final tmp = await Directory.systemTemp.createTemp('rc-upload-');
      try {
        onEvent?.call('stage', 'connecting');
        await _stopMonitor();
        final UsbResult r;
        if (job['format'] == 'hex') {
          r = await _flashAvr(port, job, tmp);
        } else {
          r = await _flashEsp32(port, job, tmp);
        }
        if (r.ok) {
          // The new sketch runs: forget the old restart loop and the unplug that the reset caused.
          _clearLoop();
          _unplugAnnounced = false;
        }
        if (r.ok || wasOpen) {
          onEvent?.call('stage', 'reopening');
          // After the reset the ESP32-S3 leaves USB for a moment and comes back.
          if (!await _reopen(const Duration(seconds: 8))) _watchForReplug();
        }
        return r;
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    } finally {
      _job = null;
      _busy = false;
    }
  }

  Future<UsbResult> _flashAvr(_Port port, Map<String, dynamic> job, Directory tmp) async {
    final hex = File('${tmp.path}\\sketch.ino.hex');
    await hex.writeAsString('${job['hex']}');
    final bytes = _hexBytes('${job['hex']}');
    onEvent?.call('stage', 'writing');
    final out = StringBuffer();
    final code = await _runJob(
        await _cli.start(['upload', '-p', port.address, '--fqbn', kFqbn['uno']!, '--input-file', hex.path, '--verbose']), (line) {
      out.writeln(line);
      if (line.contains('Writing') || line.contains('writing')) _wrote = true;
      if (line.contains('avrdude') && !line.contains('|')) _log(line);
    });
    if (_cancel) return UsbResult(false, code: 'cancelled', message: 'Cancelled.', data: {'partial': _wrote});
    if (code != 0) {
      final s = out.toString();
      final sync = s.contains('not in sync') || s.contains('not responding') || s.contains('programmer is not');
      return UsbResult(false,
          code: sync ? 'avr-sync' : 'upload',
          message: sync
              ? 'The board did not answer avrdude (not in sync).'
              : s.contains('Access is denied') || s.contains('ser_open')
                  ? 'Could not open ${port.address}. Close other apps that use it and try again.'
                  : _lastLines(s));
    }
    onEvent?.call('progress', jsonEncode({'done': bytes, 'total': bytes, 'address': 0, 'name': 'flash'}));
    return UsbResult(true, data: {'bytes': bytes, 'chip': 'ATmega328P'});
  }

  Future<UsbResult> _flashEsp32(_Port port, Map<String, dynamic> job, Directory tmp) async {
    final esptool = _cli.tool('esp32', 'esptool_py', 'esptool.exe');
    if (esptool == null) return const UsbResult(false, code: 'helper', message: 'esptool is missing. Verify once to install the ESP32 board files.');
    final args = <String>[];
    var total = 0;
    final names = <int, String>{};
    for (final part in (job['parts'] as List).cast<Map>()) {
      final data = base64Decode('${part['data']}');
      final f = File('${tmp.path}\\${part['name']}.bin');
      await f.writeAsBytes(data);
      final offset = (part['offset'] as num).toInt();
      names[offset] = '${part['name']}';
      args.addAll(['0x${offset.toRadixString(16)}', f.path]);
      total += data.length;
    }
    final chip = '${job['chip'] ?? 'auto'}';
    final baud = '${job['baud'] ?? 921600}';
    var offset = 0;
    var writing = false;
    final at = RegExp(r'Writing at 0x([0-9a-fA-F]+).*?\(\s*(\d+)\s*%\)');
    final (code, s) = await _esptool(esptool, port, [
      '--chip', chip, '--baud', baud,
      'write_flash', '-z', ...args,
    ], (line) {
      final m = at.firstMatch(line);
      if (m != null) {
        _wrote = true;
        if (!writing) {
          writing = true;
          onEvent?.call('stage', 'writing');
        }
        final addr = int.parse(m.group(1)!, radix: 16);
        for (final o in names.keys) {
          if (addr >= o && o >= offset) offset = o;
        }
        final pct = int.parse(m.group(2)!);
        onEvent?.call('progress', jsonEncode({'done': pct, 'total': 100, 'address': addr, 'name': names[offset] ?? ''}));
      } else {
        _log(line);
      }
    });
    if (_cancel) return UsbResult(false, code: 'cancelled', message: 'Cancelled.', data: {'partial': _wrote});
    if (code != 0) {
      final noBoot = !_wrote && _retryable.hasMatch(s);
      return UsbResult(false,
          code: noBoot ? 'bootloader' : 'upload',
          message: noBoot ? 'The ESP32 did not answer for ${kCatchWindow.inSeconds} seconds.' : _lastLines(s));
    }
    onEvent?.call('stage', 'resetting');
    return UsbResult(true, data: {'bytes': total, 'chip': chip.toUpperCase().replaceFirst('ESP32S', 'ESP32-S')});
  }

  /// Runs esptool on [port] with `--before default_reset` (on the ESP32-S3's own USB that is the USB-JTAG reset into
  /// the bootloader, no buttons needed). If the board is restarting, gone or not answering, it tries again the moment
  /// the port is back, for up to [kCatchWindow]. Once writing has started it does not retry. Returns the exit code
  /// and the last try's output.
  Future<(int, String)> _esptool(String esptool, _Port port, List<String> args, void Function(String line) onLine) async {
    final end = DateTime.now().add(kCatchWindow);
    var tries = 0;
    while (true) {
      tries++;
      if (!await _present(port.address)) {
        await _waitPresent(port.address, end.difference(DateTime.now()));
      }
      if (_cancel) return (1, '');
      final out = StringBuffer();
      final code = await _runJob(
          await Process.start(esptool, [
            '--port', port.address,
            '--before', 'default_reset', '--after', 'hard_reset',
            '--connect-attempts', '3',
            ...args,
          ]), (line) {
        out.writeln(line);
        onLine(line);
      });
      final s = out.toString();
      if (code == 0 || _cancel || _wrote) return (code, s);
      if (!_retryable.hasMatch(s) || DateTime.now().isAfter(end)) return (code, s);
      if (tries == 1) {
        _log('The board is restarting or not answering yet. Trying again the moment it comes back '
            '(up to ${kCatchWindow.inSeconds} seconds, no buttons needed)…');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<int> _runJob(Process p, void Function(String line) onLine) async {
    _job = p;
    if (_cancel) await killTree(p.pid);
    // avrdude draws progress bars with \r; split on both.
    void lines(String l) {
      for (final s in l.split('\r')) {
        if (s.trim().isNotEmpty) onLine(s.trim());
      }
    }

    final a = p.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(lines);
    final b = p.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(lines);
    final code = await p.exitCode;
    await a.catchError((_) {});
    await b.catchError((_) {});
    _job = null;
    return code;
  }

  @override
  Future<UsbResult> cancelFlash() async {
    _cancel = true;
    final p = _job;
    if (p != null) await killTree(p.pid);
    return const UsbResult(true);
  }

  // ---------- Test connection ----------

  @override
  Future<UsbResult> identify({required int baud, String arch = 'esp32'}) async {
    if (!supported) return UsbResult.unsupported;
    _busy = true;
    _watch?.cancel();
    _unplugNotice?.cancel();
    final port = await _portForJob();
    if (port == null) {
      _busy = false;
      return const UsbResult(false, code: 'no-port', message: 'No board found on USB. Plug it in with a data USB cable and try again.');
    }
    _port = port;
    _baud = baud;
    await _stopMonitor();
    try {
      final out = StringBuffer();
      if (arch == 'avr') {
        final avrdude = _cli.tool('arduino', 'avrdude', 'bin\\avrdude.exe');
        final conf = avrdude == null ? null : '${File(avrdude).parent.parent.path}\\etc\\avrdude.conf';
        if (avrdude == null) {
          return const UsbResult(false, code: 'helper', message: 'avrdude is missing. Verify once to install the Arduino Uno board files.');
        }
        final code = await _runJob(
            await Process.start(avrdude, ['-C', conf!, '-p', 'atmega328p', '-c', 'arduino', '-P', port.address, '-b', '115200', '-n']),
            out.writeln);
        final s = out.toString();
        if (code != 0) {
          if (s.contains('not in sync') || s.contains('not responding') || s.contains('programmer is not')) {
            return const UsbResult(false, code: 'avr-sync', message: 'The board did not answer avrdude (not in sync).');
          }
          // A different chip: avrdude stops with "signature ... expected ... (probably <chip>)".
          final other = RegExp(r'probably (\w+)').firstMatch(s);
          if (other != null) return UsbResult(true, data: {'chip': other.group(1), 'label': port.display});
          return UsbResult(false, code: 'identify', message: _lastLines(s));
        }
        // avrdude checked the chip's signature against -p atmega328p, and stops when it differs.
        return UsbResult(true, data: {'chip': 'ATmega328P', 'label': port.display});
      }
      final esptool = _cli.tool('esp32', 'esptool_py', 'esptool.exe');
      if (esptool == null) {
        return const UsbResult(false, code: 'helper', message: 'esptool is missing. Verify once to install the ESP32 board files.');
      }
      _wrote = false;
      final (code, s) = await _esptool(esptool, port, ['chip_id'], (_) {});
      final m = RegExp(r'(?:Chip is|Chip type:|Detecting chip type\.\.\.)\s*(ESP32[-\w]*)').firstMatch(s);
      if (code != 0 || m == null) {
        final noBoot = _retryable.hasMatch(s);
        return UsbResult(false,
            code: noBoot ? 'bootloader' : 'identify',
            message: noBoot ? 'The ESP32 did not answer for ${kCatchWindow.inSeconds} seconds.' : _lastLines(s));
      }
      return UsbResult(true, data: {'chip': m.group(1), 'label': port.display});
    } finally {
      _busy = false;
      if (!await _reopen(const Duration(seconds: 8))) _watchForReplug();
    }
  }
}

String _lastLines(String s) {
  final lines = s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  return lines.skip(lines.length > 3 ? lines.length - 3 : 0).join(' ');
}

/// Program bytes in an Intel HEX file (data records only).
int _hexBytes(String hex) {
  var n = 0;
  for (final l in hex.split('\n')) {
    final t = l.trim();
    if (t.length > 9 && t.startsWith(':') && t.substring(7, 9) == '00') n += int.tryParse(t.substring(1, 3), radix: 16) ?? 0;
  }
  return n;
}

UsbLink createWindowsUsb() => _NativeUsb();
