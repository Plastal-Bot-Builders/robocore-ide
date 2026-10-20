import 'dart:typed_data';

/// Native apps: no download yet (false); the caller offers the clipboard instead.
bool downloadFile(String name, Uint8List bytes, String type) => false;
