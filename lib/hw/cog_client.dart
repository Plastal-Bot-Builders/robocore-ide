// Talks to Cog on the RoboCore server (server/src/cog.js): a streamed chat reply, a suggested fix
// and a one-question quick check. The server holds the AI's key; the IDE never sees it.
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

/// Cog declined, or something went wrong. [offline]: the server could not be reached. [changed]: the server's AI is
/// not the one this device's notice named (HTTP 409).
class CogProblem extends CogEvent {
  const CogProblem(this.message, {this.offline = false, this.refused = false, this.changed = false});
  final String message;
  final bool offline, refused, changed;
}

/// Who writes Cog's answers, as the server says (GET /health → cog.by). The notice to students is written from it.
class CogBy {
  const CogBy({required this.label, this.company = '', this.where = '', this.local = false});

  /// What the AI is called, e.g. "Claude, made by Anthropic".
  final String label;

  /// The company the students' words go on to, and its country. Empty when [local].
  final String company, where;

  /// The AI runs on the RoboCore server itself: nothing goes on to another company.
  final bool local;

  static const claude = CogBy(label: 'Claude, made by Anthropic', company: 'Anthropic', where: 'the United States');

  /// A server from before it said who answers was always Claude.
  factory CogBy.fromJson(Object? j) {
    if (j is! Map) return claude;
    final label = '${j['label'] ?? ''}'.trim();
    if (label.isEmpty) return claude;
    final local = j['local'] == true;
    return CogBy(label: label, company: local ? '' : '${j['company'] ?? ''}'.trim(), where: local ? '' : '${j['where'] ?? ''}'.trim(), local: local);
  }

  Map<String, dynamic> toJson() => {'label': label, 'company': company, 'where': where, 'local': local};

  /// The same string the server makes (byId in server/src/cog.js); sent with each request as `by`.
  String get id => '$label|$company|$where|${local ? 'local' : 'hosted'}';

  /// For the About box.
  String get about => id == claude.id ? 'Claude, an AI made by Anthropic' : '$label, an AI';
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
  const CogFailure(this.message, {this.offline = false, this.changed = false});
  final String message;
  final bool offline, changed;
  @override
  String toString() => message;
}

/// RoboCore's own Cog (cog-worker/ in this repo, on Cloudflare). Every copy of the IDE uses it unless Settings → Cog
/// names another Cog server: it is open to everyone within daily limits, so there is nothing to set up.
/// (The Cloudflare account's workers.dev name was set to robocorezambia on 2026-11-22; plastalbotbuilders.com is in
/// another Cloudflare account, so it can't carry a custom domain for this Worker.)
const kCogServer = 'https://robocore-cog.robocorezambia.workers.dev';

const kCogOffline = 'Cog needs the internet. Writing code, Verify, Upload and the Serial Monitor still work.';
const kCogNoServer = 'Cog has no server address. Clear the address in Settings → Cog to use RoboCore’s own Cog.';

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

  /// [key]: the school key the server asks for (COG_KEYS), sent in X-Cog-Key. [device]: this copy of the app's random
  /// number, sent in X-Cog-Device, so an open Cog can share its daily questions between computers.
  http.Request _post(String base, String path, Map<String, Object?> body, String key, String device) =>
      http.Request('POST', Uri.parse('$base/cog/$path'))
        ..headers['Content-Type'] = 'application/json'
        ..headers.addAll({if (key.isNotEmpty) 'X-Cog-Key': key, if (device.isNotEmpty) 'X-Cog-Device': device})
        ..body = jsonEncode(body);

  /// Streams Cog's reply. Always ends with a [CogDone] or a [CogProblem].
  Stream<CogEvent> chat(String server, Map<String, Object?> body, {String key = '', String device = ''}) async* {
    final base = normalizeServerUrl(server);
    if (base.isEmpty) {
      yield const CogProblem(kCogNoServer, offline: true);
      return;
    }
    http.StreamedResponse res;
    try {
      res = await _http.send(_post(base, 'chat', body, key, device)).timeout(const Duration(seconds: 90));
    } catch (_) {
      yield const CogProblem(kCogOffline, offline: true);
      return;
    }
    if (res.statusCode != 200) {
      yield CogProblem(_error(await res.stream.bytesToString(), res.statusCode), changed: res.statusCode == 409);
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

  Future<Map<String, dynamic>> _json(String server, String path, Map<String, Object?> body, String key, String device) async {
    final base = normalizeServerUrl(server);
    if (base.isEmpty) throw const CogFailure(kCogNoServer, offline: true);
    http.StreamedResponse res;
    String text;
    try {
      res = await _http.send(_post(base, path, body, key, device)).timeout(const Duration(seconds: 120));
      text = await res.stream.bytesToString();
    } catch (_) {
      throw const CogFailure(kCogOffline, offline: true);
    }
    if (res.statusCode != 200) throw CogFailure(_error(text, res.statusCode), changed: res.statusCode == 409);
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  /// Whether the server has Cog set up and takes [key]: (ready, message). ready is null when the server can't be
  /// reached.
  Future<(bool?, String)> status(String server, {String key = ''}) async {
    final base = normalizeServerUrl(server);
    if (base.isEmpty) return (null, kCogNoServer);
    try {
      final res = await _http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 75));
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final cog = j is Map ? j['cog'] : null;
      if (cog is! Map) return (false, 'This server has no Cog yet. Update the RoboCore server.');
      if (cog['ready'] != true) return (false, 'Cog is not set up on this server yet. Whoever runs the server needs to finish its AI settings.');
      if (cog['keys'] == true) {
        final k = await _http.get(Uri.parse('$base/cog/key'), headers: {if (key.isNotEmpty) 'X-Cog-Key': key}).timeout(const Duration(seconds: 30));
        if (k.statusCode != 200) return (false, _error(utf8.decode(k.bodyBytes), k.statusCode));
      }
      final who = CogBy.fromJson(cog['by']).about;
      if (base == kCogServer) return (true, 'Answers come from $who, through RoboCore’s own Cog. Nothing to set up.');
      return (true, 'Answers come from $who, through this server.');
    } catch (_) {
      return (null, kCogOffline);
    }
  }

  /// Who answers on [server]. Null when the server can't be reached or has no Cog.
  Future<CogBy?> who(String server) async {
    final base = normalizeServerUrl(server);
    if (base.isEmpty) return null;
    try {
      final res = await _http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 75));
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final cog = j is Map ? j['cog'] : null;
      return cog is Map ? CogBy.fromJson(cog['by']) : null;
    } catch (_) {
      return null;
    }
  }

  Future<CogFix> fix(String server, Map<String, Object?> body, {String key = '', String device = ''}) async {
    final j = await _json(server, 'fix', body, key, device);
    return CogFix(explanation: '${j['explanation']}', file: '${j['file']}', newContent: '${j['newContent']}');
  }

  Future<CogCheck> check(String server, Map<String, Object?> body, {String key = '', String device = ''}) async {
    final j = await _json(server, 'check', body, key, device);
    return CogCheck(
      question: '${j['question']}',
      options: [for (final o in j['options'] as List) '$o'],
      answer: (j['answer'] as num).toInt(),
      explanation: '${j['explanation']}',
      concept: '${j['concept']}',
    );
  }
}
