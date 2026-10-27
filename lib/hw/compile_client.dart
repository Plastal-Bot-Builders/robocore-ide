// Talks to the RoboCore compile server (server/ in this repo): arduino-cli with the esp32 core
// and the RoboCore library. It turns the project's files into a program image for the board.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../engine/compiler.dart' show Problem, SourceFile;

/// The server's answer to POST /compile.
class ServerBuild {
  final bool ok;
  final List<Problem> problems;
  final String log;
  final int? flashUsed, flashMax, ramUsed, ramMax;

  /// `{format: esp32, chip, flashSize, parts: [{name, offset, size, data}]}` or `{format: hex, data}`.
  final Map<String, dynamic>? image;
  final int elapsedMs;

  /// Set when the server could not be reached or refused the request.
  final String? error;

  /// True when the server is probably asleep or unreachable (worth trying again).
  final bool retry;

  const ServerBuild({
    required this.ok,
    this.problems = const [],
    this.log = '',
    this.flashUsed,
    this.flashMax,
    this.ramUsed,
    this.ramMax,
    this.image,
    this.elapsedMs = 0,
    this.error,
    this.retry = false,
  });

  factory ServerBuild.failed(String error, {bool retry = false}) => ServerBuild(ok: false, error: error, retry: retry);

  factory ServerBuild.fromJson(Map<String, dynamic> j, {required String mainFile}) {
    final probs = <Problem>[];
    for (final p in (j['problems'] as List? ?? const [])) {
      if (p is! Map) continue;
      final file = '${p['file'] ?? mainFile}';
      final src = p['source'];
      final msg = '${p['message'] ?? ''}';
      probs.add(Problem(
        file,
        (p['line'] as num?)?.toInt() ?? 1,
        file == 'library' && src != null ? '$msg ($src)' : msg,
        severity: p['severity'] == 'warning' ? 'warning' : (p['severity'] == 'note' ? 'note' : 'error'),
        column: (p['column'] as num?)?.toInt() ?? 0,
      ));
    }
    Map<String, dynamic>? sz(String k) => ((j['sizes'] as Map?)?[k] as Map?)?.cast<String, dynamic>();
    final flash = sz('flash'), ram = sz('ram');
    return ServerBuild(
      ok: j['ok'] == true,
      problems: probs,
      log: '${j['log'] ?? ''}',
      flashUsed: (flash?['used'] as num?)?.toInt(),
      flashMax: (flash?['max'] as num?)?.toInt(),
      ramUsed: (ram?['used'] as num?)?.toInt(),
      ramMax: (ram?['max'] as num?)?.toInt(),
      image: (j['image'] as Map?)?.cast<String, dynamic>(),
      elapsedMs: (j['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }

  List<Problem> get errors => [for (final p in problems) if (p.severity == 'error') p];
}

/// Compiling on this computer instead of on the compile server: the macOS app, with arduino-cli inside it
/// (lib/hw/local_compiler_native.dart), as the Arduino IDE does.
abstract class LocalBuilder {
  /// True when this computer can build for [board].
  bool canBuild(String board);

  /// Like [CompileClient.compile]. [onLog] gets progress lines, such as the board's tools being fetched the
  /// first time they are needed.
  Future<ServerBuild> compile({required String board, required List<SourceFile> files, void Function(String line)? onLog});

  /// Deletes the copies of sketches left from builds (Reset all data). The board tools stay.
  Future<void> forgetBuilds() async {}

  /// The licences of the compiler and board tools that come with the app (About → Licences), or null.
  Future<String?> licences() async => null;
}

/// Cleans up what the user typed in Settings: adds https:// and drops a trailing slash.
String normalizeServerUrl(String raw) {
  var u = raw.trim();
  if (u.isEmpty) return '';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) {
    final local = RegExp(r'^(localhost|127\.0\.0\.1|\[::1\])(:|/|$)').hasMatch(u);
    u = '${local ? 'http' : 'https'}://$u';
  }
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

class CompileClient {
  CompileClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Compiles [files] (the first is the main .ino) for [board] (v2, devkit, nodemcu, uno).
  Future<ServerBuild> compile({
    required String serverUrl,
    required String board,
    required List<SourceFile> files,
    Duration timeout = const Duration(seconds: 170),
  }) async {
    final base = normalizeServerUrl(serverUrl);
    if (base.isEmpty) return ServerBuild.failed('No compile server is set. Add its address in Settings → Compile server.');
    final main = files.first.name;
    final body = jsonEncode({
      'board': board,
      'main': main,
      'files': [for (final f in files) {'name': f.name, 'content': f.content}],
    });
    http.Response res;
    try {
      res = await _client
          .post(Uri.parse('$base/compile'), headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(timeout);
    } on TimeoutException {
      return ServerBuild.failed('The compile server took too long to answer. If it was asleep it should be awake now: try again.',
          retry: true);
    } catch (e) {
      return ServerBuild.failed(
          'Could not reach the compile server at $base. Check the address in Settings. '
          'A free server may be waking up: wait a minute and try again.',
          retry: true);
    }
    Map<String, dynamic>? j;
    try {
      j = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      j = null;
    }
    if (res.statusCode != 200 || j == null) {
      final msg = j?['error'] as String? ?? 'The compile server answered with HTTP ${res.statusCode}.';
      final busy = res.statusCode == 429 || res.statusCode == 503 || res.statusCode == 502 || res.statusCode == 504;
      if (res.statusCode == 403) {
        return ServerBuild.failed('$msg The server does not allow this site. Add it to ALLOWED_ORIGINS on the server.');
      }
      return ServerBuild.failed(msg, retry: busy);
    }
    return ServerBuild.fromJson(j, mainFile: main);
  }

  /// GET /health: "arduino-cli 1.5.1 · esp32:esp32@3.3.12" or an error message.
  Future<(bool, String)> health(String serverUrl) async {
    final base = normalizeServerUrl(serverUrl);
    if (base.isEmpty) return (false, 'Type the server address first.');
    try {
      final res = await _client.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 75));
      if (res.statusCode != 200) return (false, 'The server answered with HTTP ${res.statusCode}.');
      final j = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
      final cores = (j['cores'] as List? ?? const []).join(', ');
      final cli = j['arduinoCli'] ?? '?';
      return (true, 'Server ready: arduino-cli $cli${cores.isEmpty ? '' : ' · $cores'}');
    } on TimeoutException {
      return (false, 'No answer in 75 s. A free server may still be waking up: try again.');
    } catch (e) {
      return (false, 'Could not reach $base. Check the address, and that the server allows this site.');
    }
  }
}
