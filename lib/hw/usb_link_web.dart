// USB link for the web app: Web Serial and esptool-js through web/robocore_usb.js.
import 'dart:convert';
import 'dart:js_interop';

import 'usb_link.dart';

@JS('navigator.serial')
external JSObject? get _webSerial;

@JS('robocoreUsb')
external _RcUsb? get _rcUsb;

@JS('document')
external _Doc get _document;

extension type _Doc._(JSObject _) implements JSObject {
  external _Script createElement(String tag);
  external _Node get head;
}

extension type _Node._(JSObject _) implements JSObject {
  external void appendChild(JSObject child);
}

extension type _Script._(JSObject _) implements JSObject {
  external set type(String value);
  external set src(String value);
}

extension type _RcUsb._(JSObject _) implements JSObject {
  external bool isOpen();
  external void setHandlers(JSFunction onText, JSFunction onEvent);
  external JSPromise<JSString> connect(int baud, bool espressifOnly);
  external JSPromise<JSString> reconnect(int baud);
  external JSPromise<JSString> disconnect();
  external JSPromise<JSString> setBaud(int baud);
  external JSPromise<JSString> write(String text);
  external JSPromise<JSString> reset();
  external JSPromise<JSString> flash(String job);
  external JSPromise<JSString> cancelFlash();
  external JSPromise<JSString> identify(int baud);
}

class _WebUsb extends UsbLink {
  Future<_RcUsb?>? _loading;

  @override
  bool get supported => _webSerial != null;

  @override
  bool get isOpen => _rcUsb?.isOpen() ?? false;

  /// Loads web/robocore_usb.js once and hooks up the callbacks.
  Future<_RcUsb?> _api() {
    return _loading ??= () async {
      if (_rcUsb == null) {
        final s = _document.createElement('script');
        s.type = 'module';
        s.src = 'robocore_usb.js';
        _document.head.appendChild(s);
        for (var i = 0; i < 200 && _rcUsb == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
      final api = _rcUsb;
      if (api == null) {
        _loading = null;
        return null;
      }
      api.setHandlers(
        ((JSString text) {
          onText?.call(text.toDart);
        }).toJS,
        ((JSString type, JSString message) {
          onEvent?.call(type.toDart, message.toDart);
        }).toJS,
      );
      return api;
    }();
  }

  Future<UsbResult> _call(JSPromise<JSString> Function(_RcUsb api) f) async {
    if (!supported) return UsbResult.unsupported;
    final api = await _api();
    if (api == null) {
      return const UsbResult(false, code: 'helper', message: 'Could not load the USB helper (robocore_usb.js). Reload the page.');
    }
    try {
      final r = await f(api).toDart;
      return UsbResult.parse(r.toDart);
    } catch (e) {
      return UsbResult(false, code: 'js', message: '$e');
    }
  }

  @override
  Future<UsbResult> connect({required int baud, bool espressifOnly = false}) =>
      _call((a) => a.connect(baud, espressifOnly));

  @override
  Future<UsbResult> reconnect({required int baud}) => _call((a) => a.reconnect(baud));

  @override
  Future<UsbResult> disconnect() => _call((a) => a.disconnect());

  @override
  Future<UsbResult> setBaud(int baud) => _call((a) => a.setBaud(baud));

  @override
  Future<UsbResult> write(String text) => _call((a) => a.write(text));

  @override
  Future<UsbResult> reset() => _call((a) => a.reset());

  @override
  Future<UsbResult> flash(Map<String, dynamic> job) => _call((a) => a.flash(jsonEncode(job)));

  @override
  Future<UsbResult> cancelFlash() => _call((a) => a.cancelFlash());

  @override
  Future<UsbResult> identify({required int baud}) => _call((a) => a.identify(baud));
}

UsbLink createUsbLink() => _WebUsb();
