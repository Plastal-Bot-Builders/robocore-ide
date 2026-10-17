// The compile server client: request shape, answer parsing and error messages.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:robocore_ide/engine/compiler.dart';
import 'package:robocore_ide/hw/compile_client.dart';

void main() {
  test('server addresses are tidied up', () {
    expect(normalizeServerUrl(' robocore-compile.onrender.com/ '), 'https://robocore-compile.onrender.com');
    expect(normalizeServerUrl('localhost:8080'), 'http://localhost:8080');
    expect(normalizeServerUrl('http://127.0.0.1:8080//'), 'http://127.0.0.1:8080');
    expect(normalizeServerUrl(''), '');
  });

  test('a successful build gives sizes, warnings and the flash image', () async {
    late Map<String, dynamic> sent;
    final client = CompileClient(
      client: MockClient((req) async {
        expect(req.url.toString(), 'https://cc.test/compile');
        expect(req.headers['Content-Type'], startsWith('application/json'));
        sent = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({
            'ok': true,
            'board': 'v2',
            'problems': [
              {'severity': 'warning', 'file': 'Blink.ino', 'line': 7, 'column': 3, 'message': 'unused variable'}
            ],
            'sizes': {
              'flash': {'used': 289306, 'max': 3145728},
              'ram': {'used': 20118, 'max': 327680}
            },
            'log': 'Sketch uses 289306 bytes (9%) of program storage space.',
            'image': {
              'format': 'esp32',
              'chip': 'esp32s3',
              'flashSize': '8MB',
              'parts': [
                {'name': 'app', 'offset': 65536, 'size': 3, 'data': 'AAEC'}
              ]
            },
            'elapsedMs': 8123,
          }),
          200,
        );
      }),
    );
    final r = await client.compile(
      serverUrl: 'cc.test',
      board: 'v2',
      files: const [SourceFile('Blink.ino', 'void setup() {}\nvoid loop() {}\n'), SourceFile('config.h', '#pragma once\n')],
    );
    expect(sent['board'], 'v2');
    expect(sent['main'], 'Blink.ino');
    expect((sent['files'] as List).length, 2);
    expect(r.ok, isTrue);
    expect(r.error, isNull);
    expect(r.flashUsed, 289306);
    expect(r.ramMax, 327680);
    expect(r.problems.single.severity, 'warning');
    expect(r.problems.single.column, 3);
    expect(r.errors, isEmpty);
    expect(r.image!['chip'], 'esp32s3');
    expect((r.image!['parts'] as List).single['offset'], 65536);
  });

  test('compile errors point at the user file; library errors name the source', () async {
    final client = CompileClient(
      client: MockClient((req) async => http.Response(
            jsonEncode({
              'ok': false,
              'problems': [
                {'severity': 'error', 'file': 'Blink.ino', 'line': 4, 'column': 1, 'message': "'foo' was not declared in this scope"},
                {'severity': 'error', 'file': 'library', 'line': 10, 'message': 'boom', 'source': 'ESP32Servo.cpp'},
              ],
            }),
            200,
          )),
    );
    final r = await client.compile(serverUrl: 'https://cc.test', board: 'v2', files: const [SourceFile('Blink.ino', 'x')]);
    expect(r.ok, isFalse);
    expect(r.errors.length, 2);
    expect(r.errors.first.line, 4);
    expect(r.errors.last.msg, 'boom (ESP32Servo.cpp)');
  });

  test('busy, refused and unreachable servers give readable messages', () async {
    Future<ServerBuild> withStatus(int code, Map<String, dynamic> body) => CompileClient(
          client: MockClient((req) async => http.Response(jsonEncode(body), code)),
        ).compile(serverUrl: 'https://cc.test', board: 'v2', files: const [SourceFile('A.ino', 'x')]);

    final busy = await withStatus(503, {'error': 'The compile server is busy. Try again in a few seconds.'});
    expect(busy.error, contains('busy'));
    expect(busy.retry, isTrue);
    final cors = await withStatus(403, {'error': 'Origin not allowed.'});
    expect(cors.error, contains('ALLOWED_ORIGINS'));

    final down = await CompileClient(client: MockClient((req) async => throw http.ClientException('connection refused')))
        .compile(serverUrl: 'https://cc.test', board: 'v2', files: const [SourceFile('A.ino', 'x')]);
    expect(down.error, contains('Could not reach the compile server'));
    expect(down.retry, isTrue);

    final none = await CompileClient().compile(serverUrl: '  ', board: 'v2', files: const [SourceFile('A.ino', 'x')]);
    expect(none.error, contains('Settings'));
  });

  test('health shows the toolchain versions', () async {
    final client = CompileClient(
      client: MockClient((req) async {
        expect(req.url.path, '/health');
        return http.Response(jsonEncode({'ok': true, 'arduinoCli': '1.5.1', 'cores': ['esp32:esp32@3.3.12']}), 200);
      }),
    );
    final (ok, msg) = await client.health('https://cc.test/');
    expect(ok, isTrue);
    expect(msg, contains('1.5.1'));
    expect(msg, contains('esp32:esp32@3.3.12'));
  });
}
