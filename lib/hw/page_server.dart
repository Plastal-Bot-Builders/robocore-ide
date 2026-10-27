// The desktop apps' web pages (the Blockly / Monaco editors, and the macOS app's USB helper): web/ files bundled as
// assets in pubspec.yaml, served on 127.0.0.1 (a random port) so they load as on the web: Monaco's workers, the
// fonts and esptool-js's module need a real http origin.
import 'dart:io';

import 'package:flutter/services.dart';

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'json': 'application/json',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'gif': 'image/gif',
  'cur': 'image/x-icon',
  'ttf': 'font/ttf',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
};

Future<Uri>? _origin;

/// The page and web/vendor come from the assets under web/, and the fonts from assets/fonts/, which the
/// page asks for as assets/assets/fonts/ (where the web build puts them).
Future<Uri> servePages() => _origin ??= () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path.substring(1);
        final key = path.startsWith('assets/assets/fonts/') ? path.substring(7) : 'web/$path';
        final res = req.response;
        try {
          if (req.method != 'GET' || path.startsWith('assets/') && !key.startsWith('assets/fonts/')) {
            throw StateError('not served');
          }
          final data = await rootBundle.load(key);
          res.headers
            ..set(HttpHeaders.contentTypeHeader, _types[key.split('.').last] ?? 'application/octet-stream')
            ..set(HttpHeaders.cacheControlHeader, 'no-store');
          res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        } catch (_) {
          res.statusCode = HttpStatus.notFound;
        }
        await res.close();
      });
      return Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    }();
