// USB link for the Windows app: the board's COM port through the same tools the Arduino IDE uses.
//  - Ports: `arduino-cli board list`. Connect picks the USB serial port with a board on it.
//  - Serial Monitor: `arduino-cli monitor` (text in on stdin, out on stdout).
//  - Upload: avrdude through `arduino-cli upload` for an Uno (its Optiboot bootloader), the esp32 core's esptool for
//    an ESP32 (parts at their flash offsets). The monitor is closed while it runs, then reopened.
//  - Test connection: the chip's own answer (avrdude reads the ATmega's signature; esptool asks the ESP32 its type).
// usb_link_native.dart hands it out on Windows; in the tests it reports itself unsupported.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'arduino_cli.dart';
import 'usb_link.dart';

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
  final _cli = ArduinoCli.instance;

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
    try {
      final port = _pick(await _ports(), espressifOnly: espressifOnly);
      if (port == null) {
        return const UsbResult(false,
            code: 'no-port', message: 'No board found on USB. Plug it in with a data USB cable (some cables only charge) and press Connect.');
      }
      _port = port;
      _baud = baud;
      await _startMonitor();
      return UsbResult(true, data: {'label': port.display});
    } on CliError catch (e) {
      return UsbResult(false, code: 'helper', message: e.message);
    } catch (e) {
      return UsbResult(false, code: 'helper', message: 'Could not open the board’s port: $e');
    }
  }

  // ---------- Serial Monitor ----------

  Future<void> _startMonitor() async {
    await _stopMonitor();
    final port = _port!;
    final p = await _cli.start(['monitor', '-p', port.address, '--config', 'baudrate=$_baud', '--quiet']);
    _monitor = p;
    _closing = false;
    p.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((t) => onText?.call(t));
    p.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((t) {
      final s = t.trim();
      if (s.isNotEmpty) onEvent?.call('log', s);
    });
    unawaited(p.exitCode.then((code) {
      if (!identical(_monitor, p)) return;
      _monitor = null;
      if (_closing) return;
      // The monitor ended by itself: the board was unplugged (or another app took the port).
      onEvent?.call('unplugged', port.display);
      _watchForReplug();
    }));
    // A port that can't be opened ends the monitor straight away.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!identical(_monitor, p)) {
      throw CliError('Could not open ${port.address}. Close other apps that use it (the Arduino IDE’s Serial Monitor, for example) and try again.');
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

  void _watchForReplug() {
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (_monitor != null || _job != null) return t.cancel();
      final port = _pick(await _ports());
      if (port == null || _monitor != null) return;
      t.cancel();
      _port = port;
      try {
        await _startMonitor();
        onEvent?.call('reconnected', port.display);
      } catch (_) {
        _watchForReplug();
      }
    });
  }

  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) {
    _port = null;
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

  @override
  Future<UsbResult> flash(Map<String, dynamic> job) async {
    if (!supported) return UsbResult.unsupported;
    final port = _pick(await _ports());
    if (port == null) {
      return const UsbResult(false, code: 'no-port', message: 'No board found on USB. Plug it in with a data USB cable and try again.');
    }
    _port = port;
    if (job['monitorBaud'] is num) _baud = (job['monitorBaud'] as num).toInt();
    _cancel = false;
    _wrote = false;
    final tmp = await Directory.systemTemp.createTemp('rc-upload-');
    final wasOpen = _monitor != null;
    try {
      onEvent?.call('stage', 'connecting');
      await _stopMonitor();
      final UsbResult r;
      if (job['format'] == 'hex') {
        r = await _flashAvr(port, job, tmp);
      } else {
        r = await _flashEsp32(port, job, tmp);
      }
      if (r.ok || wasOpen) {
        onEvent?.call('stage', 'reopening');
        try {
          await _startMonitor();
        } catch (_) {}
      }
      return r;
    } finally {
      _job = null;
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
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
    onEvent?.call('stage', 'writing');
    final out = StringBuffer();
    var offset = 0;
    final at = RegExp(r'Writing at 0x([0-9a-fA-F]+).*?\(\s*(\d+)\s*%\)');
    final code = await _runJob(
        await Process.start(esptool, [
          '--chip', chip, '--port', port.address, '--baud', baud,
          '--before', 'default_reset', '--after', 'hard_reset',
          'write_flash', '-z', ...args,
        ]), (line) {
      out.writeln(line);
      final m = at.firstMatch(line);
      if (m != null) {
        _wrote = true;
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
      final s = out.toString();
      final noBoot = s.contains('Failed to connect') || s.contains('No serial data received') || s.contains('Wrong boot mode');
      return UsbResult(false, code: noBoot ? 'bootloader' : 'upload', message: noBoot ? 'The ESP32 did not enter its bootloader.' : _lastLines(s));
    }
    onEvent?.call('stage', 'resetting');
    return UsbResult(true, data: {'bytes': total, 'chip': chip.toUpperCase().replaceFirst('ESP32S', 'ESP32-S')});
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
    final port = _pick(await _ports());
    if (port == null) {
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
      final code = await _runJob(await Process.start(esptool, ['--port', port.address, '--after', 'hard_reset', 'chip_id']), out.writeln);
      final s = out.toString();
      final m = RegExp(r'(?:Chip is|Chip type:|Detecting chip type\.\.\.)\s*(ESP32[-\w]*)').firstMatch(s);
      if (code != 0 || m == null) {
        final noBoot = s.contains('Failed to connect') || s.contains('No serial data received');
        return UsbResult(false, code: noBoot ? 'bootloader' : 'identify', message: noBoot ? 'The ESP32 did not answer.' : _lastLines(s));
      }
      return UsbResult(true, data: {'chip': m.group(1), 'label': port.display});
    } finally {
      try {
        await _startMonitor();
      } catch (_) {}
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
