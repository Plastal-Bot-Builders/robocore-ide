// Restart-loop detection (lib/hw/boot_loop.dart) and the ESP32 install check (lib/hw/arduino_cli.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/hw/arduino_cli.dart';
import 'package:robocore_ide/hw/boot_loop.dart';

void main() {
  group('BootLoopDetector', () {
    late DateTime now;
    late BootLoopDetector d;
    setUp(() {
      now = DateTime(2026, 11, 14, 12);
      d = BootLoopDetector(clock: () => now);
    });
    void wait(int ms) => now = now.add(Duration(milliseconds: ms));

    test('one unplug is not a loop; a second within a few seconds is', () {
      expect(d.onDrop(), isNull);
      expect(d.looping, isFalse);
      wait(2500);
      expect(d.onDrop(), BootLoopReason.crash);
      expect(d.looping, isTrue);
      wait(1500);
      expect(d.onDrop(), isNull, reason: 'reported once');
    });

    test('unplugs far apart are not a loop', () {
      d.onDrop();
      wait(20000);
      expect(d.onDrop(), isNull);
      expect(d.looping, isFalse);
    });

    test('a brand-new board printing "invalid header" is an empty-board loop', () {
      expect(d.onText('ESP-ROM:esp32s3-20210327\r\nrst:0x1 (POWERON),boot:0x8 (SPI_FAST_FLASH_BOOT)\r\n'), isNull);
      expect(d.onText('invalid header: 0xffffffff\r\n'), isNull);
      wait(300);
      expect(d.onText('invalid header: 0xff'), isNull, reason: 'a line counts once it ends');
      expect(d.onText('ffffff\r\n'), BootLoopReason.empty);
      expect(d.reason, BootLoopReason.empty);
    });

    test('repeated rst: lines from a crashing sketch are a crash loop', () {
      for (var i = 0; i < 2; i++) {
        expect(d.onText('Guru Meditation Error: Core 1 panic\r\nrst:0xc (RTC_SW_CPU_RST),boot:0x8\r\n'), isNull);
        wait(800);
      }
      expect(d.onText('rst:0xc (RTC_SW_CPU_RST),boot:0x8 (SPI_FAST_FLASH_BOOT)\r\n'), BootLoopReason.crash);
    });

    test('a normal start (one rst: line) is not a loop', () {
      expect(d.onText('ESP-ROM:esp32s3-20210327\nrst:0x1 (POWERON),boot:0x8 (SPI_FAST_FLASH_BOOT)\nHello RoboCore\n'), isNull);
      wait(60000);
      expect(d.onText('rst:0x15 (USB_UART_CHIP_RESET)\n'), isNull);
      expect(d.looping, isFalse);
    });

    test('the loop ends after the board stays quiet', () {
      d.onDrop();
      wait(1000);
      d.onDrop();
      expect(d.looping, isTrue);
      wait(5000);
      expect(d.settle(), isFalse);
      wait(8000);
      expect(d.settle(), isTrue);
      expect(d.looping, isFalse);
      expect(d.onDrop(), isNull, reason: 'starts counting afresh');
    });
  });

  group('ESP32 install check', () {
    late Directory data;
    setUp(() => data = Directory.systemTemp.createTempSync('a15-'));
    tearDown(() => data.deleteSync(recursive: true));

    void touch(String rel) => File('${data.path}/packages/esp32/$rel')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');

    void complete() {
      for (final f in [
        'hardware/esp32/3.3.12/platform.txt',
        'hardware/esp32/3.3.12/boards.txt',
        'hardware/esp32/3.3.12/cores/esp32/Arduino.h',
        'hardware/esp32/3.3.12/tools/partitions/boot_app0.bin',
        'tools/esp32s3-libs/3.3.12/include/esp_common/include/esp_attr.h',
        'tools/esp32s3-libs/3.3.12/flags/defines',
        'tools/xtensa-esp-elf-gcc/esp-14.2.0_20260121/bin/xtensa-esp32s3-elf-g++.exe',
        'tools/esptool_py/5.3.1/esptool.exe',
      ]) {
        touch(f);
      }
    }

    test('a complete install has nothing missing', () {
      complete();
      expect(missingEsp32Files(data.path, 'v2', sep: '/'), isEmpty);
    });

    test('a missing esp_attr.h is found', () {
      complete();
      File('${data.path}/packages/esp32/tools/esp32s3-libs/3.3.12/include/esp_common/include/esp_attr.h').deleteSync();
      expect(missingEsp32Files(data.path, 'v2', sep: '/').single, contains('esp32s3-libs'));
    });

    test('nothing installed: everything is missing', () {
      expect(missingEsp32Files(data.path, 'v2', sep: '/'), hasLength(8));
    });

    test('the ESP32 DevKit needs the esp32 libraries, not the S3 ones', () {
      complete();
      final m = missingEsp32Files(data.path, 'devkit', sep: '/');
      expect(m.any((f) => f.contains('tools/esp32-libs')), isTrue);
      expect(m.any((f) => f.contains('xtensa-esp32-elf-g++')), isTrue);
    });

    test('compiler output: a broken install, not a sketch error', () {
      expect(
          isBrokenEsp32Install(r'C:\Users\t\AppData\Local\Arduino15\packages\esp32\hardware\esp32\3.3.12\cores\esp32/esp32-hal.h:34:10: '
              'fatal error: esp_attr.h: No such file or directory'),
          isTrue);
      expect(
          isBrokenEsp32Install(r'exec: "C:\Users\t\AppData\Local\Arduino15\packages\esp32\tools\xtensa-esp-elf-gcc\x\bin\xtensa-esp32s3-elf-g++": '
              'file does not exist'),
          isTrue);
      // The sketch includes a header it doesn't have: a sketch problem, shown as it is.
      expect(
          isBrokenEsp32Install('In file included from C:\\Users\\t\\AppData\\Local\\Arduino15\\packages\\esp32\\hardware\\esp32\\3.3.12\\cores\\esp32/Arduino.h:1,\n'
              r'C:\Temp\rc-1\Blink\Blink.ino:1:10: fatal error: Missing.h: No such file or directory'),
          isFalse);
    });
  });
}
