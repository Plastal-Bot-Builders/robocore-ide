// The USB-C link to a real board: Serial Monitor and flashing.
//
// On the web this is Web Serial plus esptool-js (web/robocore_usb.js). Elsewhere (tests, and the
// native apps for now) it reports itself as unsupported and the IDE keeps using the preview board.
import 'dart:convert';

import 'usb_link_stub.dart' if (dart.library.js_interop) 'usb_link_web.dart' as impl;

/// The answer to every call: `ok`, plus a `code` and `message` when it failed.
class UsbResult {
  final bool ok;
  final String code, message;
  final Map<String, dynamic> data;
  const UsbResult(this.ok, {this.code = '', this.message = '', this.data = const {}});

  factory UsbResult.parse(String json) {
    try {
      final m = (jsonDecode(json) as Map).cast<String, dynamic>();
      return UsbResult(m['ok'] == true, code: '${m['code'] ?? ''}', message: '${m['message'] ?? ''}', data: m);
    } catch (_) {
      return UsbResult(false, code: 'bad-reply', message: 'The USB helper gave an unreadable answer.');
    }
  }

  static const unsupported = UsbResult(false,
      code: 'unsupported', message: 'USB needs the web app in Chrome or Edge on a computer (Web Serial).');
}

abstract class UsbLink {
  /// Text from the board, in whatever pieces it arrives.
  void Function(String text)? onText;

  /// unplugged, reconnected, restarted, plugged, error, log, progress, stage.
  void Function(String type, String message)? onEvent;

  /// True when this platform can talk to a board over USB.
  bool get supported;

  /// True while a port is open.
  bool get isOpen;

  /// Shows the browser's port chooser (must run from a click).
  Future<UsbResult> connect({required int baud, bool espressifOnly = false});

  /// Opens a board the user allowed before, without asking.
  Future<UsbResult> reconnect({required int baud});

  Future<UsbResult> disconnect();
  Future<UsbResult> setBaud(int baud);
  Future<UsbResult> write(String text);
  Future<UsbResult> reset();

  /// Writes a compiled program: `{parts: [{name, offset, data(base64)}], chip, boardName, baud, monitorBaud}`.
  /// Stopped with [cancelFlash], it fails with code `cancelled` (`partial` true if writing had started).
  Future<UsbResult> flash(Map<String, dynamic> job);

  /// Stops a running [flash] at its next step.
  Future<UsbResult> cancelFlash();

  /// Asks the chip its name through its bootloader (`chip`, `label`), then restarts it.
  Future<UsbResult> identify({required int baud});
}

UsbLink createUsbLink() => impl.createUsbLink();
