// App state: loading saved data safely, and Upload to a real board (fake USB link + mock compile server).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:robocore_ide/data/catalog.dart';
import 'package:robocore_ide/hw/compile_client.dart';
import 'package:robocore_ide/hw/usb_link.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeUsb extends UsbLink {
  bool open = false;
  bool failBootloader = false;
  Map<String, dynamic>? flashed;
  String chip = 'ESP32-S3 (QFN56) (revision v0.2)';
  // Set to make flash() wait until Stop (cancelFlash) or until it is completed.
  Completer<void>? flashGate;
  bool flashing = false, cancelled = false;
  final written = <String>[];
  String? resetArch, identifyArch;

  @override
  bool get supported => true;
  @override
  bool get isOpen => open;

  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) async {
    open = true;
    return const UsbResult(true, data: {'ok': true, 'label': 'ESP32-S3 USB (303A:1001)'});
  }

  @override
  Future<UsbResult> reconnect({required int baud}) => connect(baud: baud);

  @override
  Future<UsbResult> disconnect() async {
    open = false;
    return const UsbResult(true);
  }

  @override
  Future<UsbResult> setBaud(int baud) async => const UsbResult(true);

  @override
  Future<UsbResult> write(String text) async {
    written.add(text);
    return const UsbResult(true);
  }

  @override
  Future<UsbResult> reset({String arch = 'esp32'}) async {
    resetArch = arch;
    return const UsbResult(true);
  }

  @override
  Future<UsbResult> flash(Map<String, dynamic> job) async {
    if (failBootloader && job['format'] == 'hex') return const UsbResult(false, code: 'avr-sync', message: 'The board did not answer its bootloader.');
    if (failBootloader) return const UsbResult(false, code: 'bootloader', message: 'Failed to connect with the device');
    if (flashGate != null) {
      flashing = true;
      onEvent?.call('stage', 'writing');
      await flashGate!.future;
      flashing = false;
      if (cancelled) return const UsbResult(false, code: 'cancelled', message: 'Upload cancelled.', data: {'partial': true});
    }
    flashed = job;
    onEvent?.call('stage', 'connecting');
    onEvent?.call('progress', jsonEncode({'name': 'app', 'address': 65536, 'done': 50, 'total': 100}));
    onEvent?.call('progress', jsonEncode({'name': 'app', 'address': 65536, 'done': 100, 'total': 100}));
    onText?.call('RoboCore V2 ready\r\n');
    return UsbResult(true, data: {'ok': true, 'chip': job['format'] == 'hex' ? 'ATmega328P' : 'ESP32-S3', 'bytes': 100, 'reopened': true});
  }

  @override
  Future<UsbResult> cancelFlash() async {
    if (flashing) {
      cancelled = true;
      flashGate?.complete();
    }
    return UsbResult(true, data: {'cancelling': flashing});
  }

  @override
  Future<UsbResult> identify({required int baud, String arch = 'esp32'}) async {
    identifyArch = arch;
    if (failBootloader && arch == 'avr') return const UsbResult(false, code: 'avr-sync', message: 'The board did not answer its bootloader.');
    if (failBootloader) return const UsbResult(false, code: 'bootloader', message: 'Failed to connect with the device');
    return UsbResult(true, data: {'chip': chip, 'label': 'ESP32-S3 USB (303A:1001)', 'reopened': true});
  }
}

http.Response _ok() => http.Response(
      jsonEncode({
        'ok': true,
        'problems': [],
        'sizes': {
          'flash': {'used': 300000, 'max': 3145728},
          'ram': {'used': 20000, 'max': 327680}
        },
        'log': 'Sketch uses 300000 bytes (9%) of program storage space.',
        'image': {
          'format': 'esp32',
          'chip': 'esp32s3',
          'parts': [
            {'name': 'bootloader', 'offset': 0, 'size': 3, 'data': 'AAEC'},
            {'name': 'app', 'offset': 65536, 'size': 3, 'data': 'AAEC'}
          ]
        },
      }),
      200,
    );

// An Arduino Uno build: Intel HEX for its bootloader.
http.Response _unoOk() => http.Response(
      jsonEncode({
        'ok': true,
        'problems': [],
        'sizes': {
          'flash': {'used': 924, 'max': 32256},
          'ram': {'used': 9, 'max': 2048}
        },
        'log': 'Sketch uses 924 bytes (2%) of program storage space. Maximum is 32256 bytes.',
        'image': {'format': 'hex', 'data': ':100000000C945C000C946E000C946E000C946E00CA\n:00000001FF\n'},
      }),
      200,
    );

String _store(List<dynamic> projects, {String port = 'sim', String server = ''}) => jsonEncode({
      'v': 1,
      'user': 'Fredrick',
      'board': 'v2',
      'port': port,
      'baud': 115200,
      'connected': true,
      'settings': {'compileServer': server},
      'libs': {'esp32servo': true},
      'projects': projects,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one damaged project does not throw away the others', () async {
    final good = projectFrom(exampleById('blink'), name: 'Keep me').toJson();
    SharedPreferences.setMockInitialValues({
      'robocore-ide-v1': _store([
        good,
        {'id': 'x', 'name': 'Broken'}, // no files
        'not even a map',
      ]),
    });
    final s = AppState(usbLink: FakeUsb());
    await s.load();
    s.sim.stop();
    expect(s.projects.map((p) => p.name).toList(), ['Keep me']);
    expect(s.loadNotice, contains('2 saved projects could not be opened'));
    final prefs = await SharedPreferences.getInstance();
    final aside = prefs.getKeys().where((k) => k.startsWith('robocore-ide-v1-damaged-')).toList();
    expect(aside, hasLength(1));
    expect(prefs.getString(aside.single), contains('Broken'));
  });

  test('unreadable saved data is kept aside before the samples are restored', () async {
    SharedPreferences.setMockInitialValues({'robocore-ide-v1': '{not json'});
    final s = AppState(usbLink: FakeUsb());
    await s.load();
    s.sim.stop();
    expect(s.projects, isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    final aside = prefs.getKeys().where((k) => k.startsWith('robocore-ide-v1-unreadable-'));
    expect(prefs.getString(aside.single), '{not json');
  });

  test('old port names become the preview board', () async {
    SharedPreferences.setMockInitialValues({
      'robocore-ide-v1': _store([projectFrom(exampleById('blink')).toJson()], port: '/dev/cu.usbmodem1101'),
    });
    final s = AppState(usbLink: FakeUsb());
    await s.load();
    s.sim.stop();
    expect(s.port, kPortSim);
    expect(s.linked, isTrue);
  });

  group('Profile', () {
    test('a new device has no name until the welcome screen is filled in', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(usbLink: FakeUsb());
      await s.load();
      s.sim.stop();
      expect(s.needsProfile, isTrue);
      expect(s.user, isEmpty);
      expect(s.projects.first.name, 'Blink LED');
      expect(s.validateProfileName('  '), isNotNull);
      s.setProfile(name: '  Thandi   Mokoena ', school: 'Grade 7B');
      expect(s.user, 'Thandi Mokoena');
      expect(s.firstName, 'Thandi');
      expect(s.initials, 'TM');

      final again = AppState(usbLink: FakeUsb());
      await again.load();
      again.sim.stop();
      expect(again.needsProfile, isFalse);
      expect(again.user, 'Thandi Mokoena');
      expect(again.school, 'Grade 7B');
    });

    test('saves from before profiles (sample name "Fredrick") ask for a name once, and keep the projects', () async {
      SharedPreferences.setMockInitialValues({
        'robocore-ide-v1': _store([projectFrom(exampleById('blink'), name: 'My robot').toJson()]),
      });
      final s = AppState(usbLink: FakeUsb());
      await s.load();
      s.sim.stop();
      expect(s.needsProfile, isTrue);
      expect(s.projects.single.name, 'My robot');
    });

    test('one-word names give one initial', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(usbLink: FakeUsb());
      await s.load();
      s.sim.stop();
      s.setProfile(name: 'sipho');
      expect(s.initials, 'S');
    });
  });

  group('Upload to a real board', () {
    late FakeUsb usb;
    late AppState s;
    late List<Map<String, dynamic>> requests;
    http.Response Function() reply = _ok;
    Completer<void>? serverGate;

    setUp(() async {
      usb = FakeUsb();
      requests = [];
      reply = _ok;
      serverGate = null;
      SharedPreferences.setMockInitialValues({
        'robocore-ide-v1': _store([projectFrom(exampleById('blink'), name: 'Blink LED').toJson()],
            port: 'usb', server: 'https://cc.test'),
      });
      s = AppState(
        usbLink: usb,
        compileClient: CompileClient(
          client: MockClient((req) async {
            requests.add((jsonDecode(req.body) as Map).cast<String, dynamic>());
            if (serverGate != null) await serverGate!.future;
            return reply();
          }),
        ),
      );
      await s.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      s.openProject(s.projects.first.id);
    });

    tearDown(() => s.sim.stop());

    test('reconnects to the allowed board at start-up', () {
      expect(s.onUsb, isTrue);
      expect(s.usbOpen, isTrue);
      expect(s.usbLabel, 'ESP32-S3 USB (303A:1001)');
      expect(s.sim.running, isFalse);
    });

    test('compiles on the server, flashes every part and reopens the monitor', () async {
      await s.upload();
      expect(requests.single['board'], 'v2');
      expect(requests.single['main'], 'Blink.ino');
      expect(usb.flashed!['chip'], 'esp32s3');
      expect((usb.flashed!['parts'] as List).length, 2);
      expect(usb.flashed!['monitorBaud'], 115200);
      final out = s.output.map((o) => o.text).join('\n');
      expect(out, contains('Writing app at 0x00010000… (50 %)'));
      expect(out, contains('Upload complete'));
      expect(s.stateLabel, 'Uploaded');
      expect(s.busy, isNull);
      expect(s.verified!.size, 300000);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(s.log.map((l) => l.text), contains('RoboCore V2 ready'));
    });

    test('compile errors go to Problems and nothing is flashed', () async {
      reply = () => http.Response(
            jsonEncode({
              'ok': false,
              'problems': [
                {'severity': 'error', 'file': 'Blink.ino', 'line': 3, 'column': 5, 'message': "expected ';' before '}' token"}
              ],
            }),
            200,
          );
      await s.upload();
      expect(usb.flashed, isNull);
      expect(s.problems.single.line, 3);
      expect(s.panelTab, 'problems');
      expect(s.stateLabel, 'Errors');
    });

    test('no bootloader answer shows the BOOT + RESET tip', () async {
      usb.failBootloader = true;
      await s.upload();
      expect(s.output.map((o) => o.text), contains(kBootTip));
      expect(s.stateLabel, 'Upload failed');
    });

    test('without a compile server, Upload says how to set one up', () async {
      s.setCompileServer('');
      await s.upload();
      expect(requests, isEmpty);
      expect(s.output.last.text, contains('Settings → Compile server'));
    });

    test('Verify uses the server when one is set', () async {
      await s.verify();
      expect(requests, hasLength(1));
      expect(usb.flashed, isNull);
      expect(s.stateLabel, 'Verified');
    });

    test('serial text goes to the board; unplug and replug are reported', () async {
      s.sendSerial('led on');
      expect(usb.written, ['led on\n']);
      usb.onEvent!('unplugged', 'ESP32-S3 USB (303A:1001)');
      expect(s.usbOpen, isFalse);
      expect(s.log.last.text, contains('unplugged'));
      usb.onEvent!('reconnected', 'ESP32-S3 USB (303A:1001)');
      expect(s.usbOpen, isTrue);
      expect(s.log.last.text, contains('reconnected'));
    });

    test('Stop while compiling cancels the upload, and the late answer is ignored', () async {
      serverGate = Completer<void>();
      expect(s.canStop, isFalse);
      final up = s.upload();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(s.busy, 'upload');
      expect(s.canStop, isTrue);
      s.stop();
      expect(s.busy, isNull);
      expect(s.stateLabel, 'Cancelled');
      serverGate!.complete();
      await up;
      expect(usb.flashed, isNull);
      expect(s.stateLabel, 'Cancelled');
      expect(s.output.map((o) => o.text), contains('Upload cancelled.'));
      expect(s.output.map((o) => o.text).join('\n'), isNot(contains('Compiled in')));
    });

    test('Stop while flashing asks the flasher to stop and says the program is incomplete', () async {
      usb.flashGate = Completer<void>();
      final up = s.upload();
      for (var i = 0; i < 50 && !usb.flashing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(usb.flashing, isTrue);
      s.stop();
      await up;
      expect(usb.cancelled, isTrue);
      expect(usb.flashed, isNull);
      expect(s.busy, isNull);
      expect(s.stateLabel, 'Cancelled');
      expect(s.output.last.text, contains('cancelled part-way'));
    });

    test('Test connection asks the chip its name', () async {
      await s.testConnection();
      expect(s.conn!.kind, 'ok');
      expect(s.conn!.text, contains('ESP32-S3 (QFN56) (revision v0.2)'));
      expect(s.toast, 'Board answered');
      expect(s.toastBody, startsWith('ESP32-S3 (QFN56) (revision v0.2) on '));
      expect(s.busy, isNull);
      s.closeToast();
    });

    test('Test connection: a different chip, or no answer', () async {
      usb.chip = 'ESP32-D0WD-V3 (revision v3.1)';
      await s.testConnection();
      expect(s.conn!.kind, 'err');
      expect(s.conn!.text, contains('Board Setup is set to RoboCore V2'));
      usb.failBootloader = true;
      await s.testConnection();
      expect(s.conn!.kind, 'err');
      expect(s.conn!.text, contains('did not answer'));
      s.closeToast();
    });

    test('an Uno project uploads its HEX through the bootloader, on USB (not USB-C)', () async {
      s.cur!.board = 'uno';
      reply = _unoOk;
      await s.upload();
      expect(requests.single['board'], 'uno');
      expect(usb.flashed!['format'], 'hex');
      expect(usb.flashed!['hex'], startsWith(':100000000C945C00'));
      expect(usb.flashed!['chip'], 'ATmega328P');
      expect(usb.flashed!['pageSize'], 128);
      expect(usb.flashed!['max'], 32256);
      expect(usb.flashed!['monitorBaud'], 115200);
      final out = s.output.map((o) => o.text).join('\n');
      expect(out, contains('Uploading to the Arduino Uno R3 on USB…'));
      expect(out, contains('bytes written to the ATmega328P'));
      expect(out, isNot(contains('USB-C')));
      expect(s.stateLabel, 'Uploaded');
      expect(s.verified!.size, 924);
    });

    test('an Uno that does not answer its bootloader gets the Uno tip, not BOOT + RESET', () async {
      s.cur!.board = 'uno';
      reply = _unoOk;
      usb.failBootloader = true;
      await s.upload();
      final out = s.output.map((o) => o.text);
      expect(out, contains(kAvrTip));
      expect(out, isNot(contains(kBootTip)));
      expect(s.stateLabel, 'Upload failed');
      s.closeToast();
    });

    test('Test connection and Reset board on an Uno use its bootloader and DTR', () async {
      s.setDefaultBoard('uno');
      s.go(Screen.board); // both buttons are in Board Setup, which follows the default board
      usb.chip = 'ATmega328P';
      await s.testConnection();
      expect(usb.identifyArch, 'avr');
      expect(s.conn!.kind, 'ok');
      expect(s.conn!.text, contains('ATmega328P'));
      await s.resetUsbBoard();
      expect(usb.resetArch, 'avr');
      usb.failBootloader = true;
      await s.testConnection();
      expect(s.conn!.text, contains('did not answer its bootloader'));
      expect(s.conn!.text, contains('press Test connection again'));
      s.closeToast();
    });

    test('text without a newline still shows up', () async {
      usb.onText!('Type > ');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(s.log.last.text, 'Type > ');
    });
  });
}
