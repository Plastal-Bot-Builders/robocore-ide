// USB link for the macOS app, which has no Web Serial: the web app's USB helper (web/robocore_usb.js and
// esptool-js, the code tested in Chrome) runs in a hidden WebView (web/robocore_usb_host.html) on a Web Serial
// stand-in (web/robocore_serial_shim.js) whose ports are the Mac's serial ports (macos/Runner/SerialPorts.swift).
// The other native apps, and tests, report USB as unsupported for now.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'page_server.dart';
import 'usb_link.dart';

const _serial = MethodChannel('robocore/serial');
const _serialEvents = EventChannel('robocore/serial/events');

/// The ports the user picked before, so the app can reopen them without asking (as Chrome remembers).
const _grantedKey = 'rc-usb-granted';

typedef PortInfo = Map<String, Object?>;

class _MacUsb extends UsbLink {
  _MacUsb() {
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('RoboCoreHost', onMessageReceived: (m) => unawaited(_message(m.message)));
    _serialEvents.receiveBroadcastStream().listen(_serialEvent);
    unawaited(servePages().then((origin) => _controller.loadRequest(origin.replace(path: '/robocore_usb_host.html'))));
  }

  final _controller = WebViewController();
  final _ready = Completer<void>();
  final _calls = <int, Completer<String>>{};
  var _nextCall = 1;
  var _open = false;
  List<PortInfo>? _granted;

  @override
  bool get supported => true;

  @override
  bool get isOpen => _open;

  // WebKit slows a page that is not in a window, so the helper's WebView sits in the window, 1 px, under the app.
  @override
  late final Widget hostView = WebViewWidget(controller: _controller);

  // ---------------------------------------------------------------- the helper page

  Future<void> _message(String json) async {
    final List<Object?> m;
    try {
      m = jsonDecode(json) as List<Object?>;
    } on FormatException {
      return;
    }
    switch (m.first) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
        unawaited(_devices());
      case 'result':
        _open = m[3] == true;
        _calls.remove(m[1])?.complete(m[2] as String);
      case 'text':
        onText?.call(m[1] as String);
      case 'event':
        _open = m[3] == true;
        onEvent?.call(m[1] as String, m[2] as String);
      case 'serial':
        await _serialRequest(m[1] as int, m[2] as String, m.sublist(3));
    }
  }

  void _run(String js) => unawaited(_controller.runJavaScript(js).catchError((Object e) {
        debugPrint('RoboCore USB: $e');
      }));

  /// A robocoreUsb method on the page (robocore_usb.js); every one answers with a JSON string.
  Future<UsbResult> _call(String method, [List<Object?> args = const []]) async {
    try {
      await _ready.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return const UsbResult(false, code: 'helper', message: 'The USB helper did not start. Restart RoboCore.');
    }
    final id = _nextCall++;
    final done = Completer<String>();
    _calls[id] = done;
    _run('rcUsbCall($id, ${jsonEncode(method)}, ${jsonEncode(args)})');
    return UsbResult.parse(await done.future);
  }

  // ---------------------------------------------------------------- Web Serial, for the page

  void _reply(int id, bool ok, Object? value) => _run('rcSerialHost.reply($id, $ok, ${jsonEncode(value)})');

  Future<void> _serialRequest(int id, String op, List<Object?> a) async {
    try {
      switch (op) {
        case 'request':
          _reply(id, true, await _request(a.first as List<Object?>));
        case 'granted':
          _reply(id, true, await _plugged());
        case 'open':
          _reply(id, true, await _serial.invokeMethod<int>('open', {'path': a[0], 'baud': a[1]}));
        case 'write':
          _reply(id, true, await _serial.invokeMethod<bool>('write', {'id': a[0], 'data': base64Decode(a[1] as String)}));
        case 'signals':
          _reply(id, true, await _serial.invokeMethod<bool>('signals', {'id': a[0], 'dtr': a[1], 'rts': a[2]}));
        case 'close':
          _reply(id, true, await _serial.invokeMethod<bool>('close', {'id': a[0]}));
        default:
          _reply(id, false, 'Unknown serial request $op');
      }
    } on PlatformException catch (e) {
      _reply(id, false, e.message ?? e.code);
    }
  }

  void _serialEvent(dynamic e) {
    final m = (e as Map).cast<String, Object?>();
    switch (m['type']) {
      case 'data':
        _run('rcSerialHost.data(${m['id']}, "${base64Encode(m['data'] as Uint8List)}")');
      case 'closed':
        _run('rcSerialHost.closed(${m['id']}, ${jsonEncode(m['reason'])})');
      case 'devices':
        unawaited(_devices());
    }
  }

  /// Tells the page which allowed ports are plugged in now (it fires connect / disconnect from that).
  Future<void> _devices() async {
    if (!_ready.isCompleted) return;
    _run('rcSerialHost.devices(${jsonEncode(await _plugged())})');
  }

  Future<List<PortInfo>> _ports() async {
    final list = await _serial.invokeListMethod<Map<Object?, Object?>>('list') ?? [];
    return [for (final p in list) p.cast<String, Object?>()];
  }

  Future<List<PortInfo>> _grantedPorts() async {
    if (_granted != null) return _granted!;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_grantedKey);
      _granted = saved == null ? [] : [for (final p in jsonDecode(saved) as List) (p as Map).cast<String, Object?>()];
    } catch (_) {
      _granted = [];
    }
    return _granted!;
  }

  /// The same board: its USB serial number when it has one, else its ids and port.
  static bool _same(PortInfo a, PortInfo b) => a['serial'] != null || b['serial'] != null
      ? a['serial'] == b['serial'] && a['vid'] == b['vid']
      : a['vid'] == b['vid'] && a['pid'] == b['pid'] && a['path'] == b['path'];

  /// The allowed boards that are plugged in now (with their current port, which can change on a re-plug).
  Future<List<PortInfo>> _plugged() async {
    final granted = await _grantedPorts();
    return [
      for (final p in await _ports())
        if (granted.any((g) => _same(g, p))) p
    ];
  }

  /// The port chooser (Chrome shows its own): USB ports only, those matching [filters] (usbVendorId).
  Future<PortInfo?> _request(List<Object?> filters) async {
    final vids = [for (final f in filters) (f as Map)['usbVendorId']].whereType<int>().toSet();
    final ports = [
      for (final p in await _ports())
        if (p['vid'] != null && (vids.isEmpty || vids.contains(p['vid']))) p
    ];
    final chosen = await choosePort?.call(ports);
    if (chosen == null) return null;
    final granted = await _grantedPorts();
    granted
      ..removeWhere((g) => _same(g, chosen))
      ..add(chosen);
    try {
      (await SharedPreferences.getInstance()).setString(_grantedKey, jsonEncode(granted));
    } catch (_) {}
    return chosen;
  }

  // ---------------------------------------------------------------- UsbLink

  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) => _call('connect', [baud, espressifOnly]);

  @override
  Future<UsbResult> reconnect({required int baud}) => _call('reconnect', [baud]);

  @override
  Future<UsbResult> disconnect() => _call('disconnect');

  @override
  Future<UsbResult> setBaud(int baud) => _call('setBaud', [baud]);

  @override
  Future<UsbResult> write(String text) => _call('write', [text]);

  @override
  Future<UsbResult> reset({String arch = 'esp32'}) => _call('reset', [arch]);

  @override
  Future<UsbResult> flash(Map<String, dynamic> job) => _call('flash', [jsonEncode(job)]);

  @override
  Future<UsbResult> cancelFlash() => _call('cancelFlash');

  @override
  Future<UsbResult> identify({required int baud, String arch = 'esp32'}) => _call('identify', [baud, arch]);
}

/// Every call fails as unsupported (the other native apps for now, and tests).
class _NoUsb extends UsbLink {
  @override
  bool get supported => false;
  @override
  bool get isOpen => false;
  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) async => UsbResult.unsupported;
  @override
  Future<UsbResult> reconnect({required int baud}) async => UsbResult.unsupported;
  @override
  Future<UsbResult> disconnect() async => const UsbResult(true);
  @override
  Future<UsbResult> setBaud(int baud) async => const UsbResult(true);
  @override
  Future<UsbResult> write(String text) async => UsbResult.unsupported;
  @override
  Future<UsbResult> reset({String arch = 'esp32'}) async => UsbResult.unsupported;
  @override
  Future<UsbResult> flash(Map<String, dynamic> job) async => UsbResult.unsupported;
  @override
  Future<UsbResult> cancelFlash() async => const UsbResult(true);
  @override
  Future<UsbResult> identify({required int baud, String arch = 'esp32'}) async => UsbResult.unsupported;
}

UsbLink createUsbLink() => defaultTargetPlatform == TargetPlatform.macOS ? _MacUsb() : _NoUsb();
