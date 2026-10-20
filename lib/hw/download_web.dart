import 'dart:js_interop';
import 'dart:typed_data';

@JS('document')
external _Doc get _document;

extension type _Doc._(JSObject _) implements JSObject {
  external _Link createElement(String tag);
  external _Node get body;
}

extension type _Node._(JSObject _) implements JSObject {
  external void appendChild(JSObject child);
}

extension type _Link._(JSObject _) implements JSObject {
  external set href(String v);
  external set download(String v);
  external void click();
  external void remove();
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

@JS('URL.createObjectURL')
external String _objectUrl(_Blob blob);

@JS('URL.revokeObjectURL')
external void _revoke(String url);

/// Starts the browser's download of [bytes] as [name]. True when it started.
bool downloadFile(String name, Uint8List bytes, String type) {
  try {
    final blob = _Blob(<JSAny>[bytes.toJS].toJS, {'type': type}.jsify()! as JSObject);
    final url = _objectUrl(blob);
    final a = _document.createElement('a')
      ..href = url
      ..download = name;
    _document.body.appendChild(a);
    a.click();
    a.remove();
    // The download has its own copy once it starts; free the URL a moment later.
    Future<void>.delayed(const Duration(seconds: 30), () => _revoke(url));
    return true;
  } catch (_) {
    return false;
  }
}
