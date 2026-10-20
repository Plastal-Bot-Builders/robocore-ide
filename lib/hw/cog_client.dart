// Talks to Cog on the RoboCore server (server/src/cog.js): a streamed chat reply, a suggested fix
// and a one-question quick check. The server holds the Anthropic API key; the IDE never sees it.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'compile_client.dart' show normalizeServerUrl;

/// One piece of a streamed reply.
sealed class CogEvent {
  const CogEvent();
}

class CogText extends CogEvent {
  const CogText(this.text);
  final String text;
}

class CogDone extends CogEvent {
  const CogDone(this.stop);
  final String stop;
}

/// Cog declined, or something went wrong. [offline]: the server could not be reached.
class CogProblem extends CogEvent {
  const CogProblem(this.message, {this.offline = false, this.refused = false});
  final String message;
  final bool offline, refused;
}

class CogFix {
  const CogFix({required this.explanation, required this.file, required this.newContent});
  final String explanation, file, newContent;
}

class CogCheck {
  const CogCheck({required this.question, required this.options, required this.answer, required this.explanation, required this.concept});
  final String question, explanation, concept;
  final List<String> options;
  final int answer;
}

class CogFailure implements Exception {
  const CogFailure(this.message, {this.offline = false});
  final String message;
  final bool offline;
  @override
  String toString() => message;
}

const kCogOffline = 'Cog needs the internet. Writing code, Verify, Upload and the Serial Monitor still work.';
const kCogNoServer = 'Cog works through the RoboCore server. Add its address in Settings → Real board and upload.';

class CogClient {
  CogClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  String _error(String body, int status) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is String) return m['error'] as String;
    } catch (_) {}
    return 'Cog answered with HTTP $status.';
  }

  http.Request _post(String base, String path, Map<String, Object?> body) => http.Request('POST', Uri.parse('$base/cog/$path'))
    ..headers['Content-Type'] = 'application/json'
    ..body = jsonEncode(body);

  /// Streams Cog's reply. Always ends with a [CogDone] or a [CogProblem].
  Stream<CogEvent> chat(String server, Map<String, Object?> body) async* {
    final base = normalizeServerUrl(server);
    if (base.isEmpty) {
      yield const CogProblem(kCogNoServer, offline: true);
      return;
    }
    http.StreamedResponse res;
    try {
      res = await _http.send(_post(base, 'chat', body)).timeout(const Duration(seconds: 90));
    } catch (_) {
      yield const CogProblem(kCogOffline, offline: true);
      return;
    }
    if (res.statusCode != 200) {
      yield CogProblem(_error(await res.stream.bytesToString(), res.statusCode));
      return;
    }
    var finished = false;
    try {
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final m = jsonDecode(line.substring(6));
        if (m is! Map) continue;
        switch (m['t']) {
          case 'text':
            yield CogText('${m['v'] ?? ''}');
          case 'refusal':
            finished = true;
            yield CogProblem('${m['message'] ?? 'Cog can’t help with that one.'}', refused: true);
          case 'error':
            finished = true;
            yield CogProblem('${m['message'] ?? 'Cog hit a problem. Try again.'}');
          case 'done':
            if (!finished) yield CogDone('${m['stop'] ?? ''}');
            finished = true;
        }
      }
    } catch (_) {
      if (!finished) yield const CogProblem('The connection to Cog dropped. Try again.', offline: true);
      return;
    }
    if (!finished) yield const CogProblem('Cog stopped before finishing. Try again.');
  }

  Future<Map<String, dynamic>> _json(String server, String path, Map<String, Object?> body) async {
    final base = normalizeServerUrl(server);
    if (base.isEmpty) throw const CogFailure(kCogNoServer, offline: true);
    http.StreamedResponse res;
    String text;
    try {
      res = await _http.send(_post(base, path, body)).timeout(const Duration(seconds: 120));
      text = await res.stream.bytesToString();
    } catch (_) {
      throw const CogFailure(kCogOffline, offline: true);
    }
    if (res.statusCode != 200) throw CogFailure(_error(text, res.statusCode));
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  /// Whether the server has Cog set up: (ready, message). ready is null when the server can't be reached.
  Future<(bool?, String)> status(String server) async {
    final base = normalizeServerUrl(server);
    if (base.isEmpty) return (null, kCogNoServer);
    try {
      final res = await _http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 75));
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final cog = j is Map ? j['cog'] : null;
      if (cog is! Map) return (false, 'This server has no Cog yet. Update the RoboCore server.');
      if (cog['ready'] != true) return (false, 'Cog is not set up on this server yet: it needs an Anthropic API key (ANTHROPIC_API_KEY).');
      return (true, 'Answers come from ${cog['model']} through this server.');
    } catch (_) {
      return (null, kCogOffline);
    }
  }

  Future<CogFix> fix(String server, Map<String, Object?> body) async {
    final j = await _json(server, 'fix', body);
    return CogFix(explanation: '${j['explanation']}', file: '${j['file']}', newContent: '${j['newContent']}');
  }

  Future<CogCheck> check(String server, Map<String, Object?> body) async {
    final j = await _json(server, 'check', body);
    return CogCheck(
      question: '${j['question']}',
      options: [for (final o in j['options'] as List) '$o'],
      answer: (j['answer'] as num).toInt(),
      explanation: '${j['explanation']}',
      concept: '${j['concept']}',
    );
  }
}
