// Cog in the IDE: the client against a fake server, and the steps (explain → hints → fix → Apply →
// quick check → learned) against a fake client. The server side has its own tests (server/test).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:robocore_ide/data/catalog.dart';
import 'package:robocore_ide/engine/compiler.dart';
import 'package:robocore_ide/hw/cog_client.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/state/cog.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:robocore_ide/ui/cog/cog_panel.dart' show cogDiff;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state_test.dart' show FakeUsb;

/// Answers like the server would, and remembers what it was asked.
class FakeCog extends CogClient {
  FakeCog() : super(client: MockClient((_) async => http.Response('', 500)));
  final asked = <Map<String, Object?>>[];
  String reply = 'Arduino names are case-sensitive.';

  @override
  Stream<CogEvent> chat(String server, Map<String, Object?> body) async* {
    asked.add(body);
    for (final w in reply.split(' ')) {
      yield CogText('$w ');
    }
    yield const CogDone('end_turn');
  }

  @override
  Future<CogFix> fix(String server, Map<String, Object?> body) async {
    asked.add(body);
    return const CogFix(explanation: 'Use a capital W.', file: 'Blink.ino', newContent: 'void setup() {}\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); }\n');
  }

  @override
  Future<CogCheck> check(String server, Map<String, Object?> body) async {
    asked.add(body);
    return const CogCheck(question: 'Which compiles?', options: ['delay(1);', 'Delay(1);'], answer: 0, explanation: 'Lower case.', concept: 'Names are case-sensitive');
  }
}

Future<(AppState, FakeCog)> openProject() async {
  SharedPreferences.setMockInitialValues({});
  final fake = FakeCog();
  final s = AppState(usbLink: FakeUsb(), cogClient: fake);
  await s.load();
  s.updateSettings((x) => x.compileServer = 'http://localhost:8080');
  s.openExample(kExamples.firstWhere((e) => e.blocksFor('v2') != null).id);
  s.setMode('code');
  final p = s.cur!;
  p.files.first.name = 'Blink.ino';
  p.files.first.content = 'void setup() {}\nvoid loop() { digitalwrite(LED_BUILTIN, HIGH); }\n';
  s.problems = [const Problem('Blink.ino', 2, "'digitalwrite' was not declared in this scope", column: 15)];
  return (s, fake);
}

void main() {
  group('CogClient', () {
    test('reads a streamed reply', () async {
      final client = CogClient(client: MockClient.streaming((req, body) async {
        expect(req.url.toString(), 'http://localhost:8080/cog/chat');
        final sse = 'data: {"t":"text","v":"Hello "}\n\ndata: {"t":"text","v":"there"}\n\ndata: {"t":"done","stop":"end_turn"}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200, headers: {'content-type': 'text/event-stream'});
      }));
      final ev = await client.chat('localhost:8080', {'task': 'chat'}).toList();
      expect(ev.whereType<CogText>().map((e) => e.text).join(), 'Hello there');
      expect(ev.last, isA<CogDone>());
    });

    test('says offline when the server cannot be reached, and what to set when there is none', () async {
      final down = CogClient(client: MockClient((_) => Future.error(Exception('no network'))));
      final ev = await down.chat('http://localhost:8080', {}).toList();
      expect((ev.single as CogProblem).offline, isTrue);
      final none = await down.chat('', {}).toList();
      expect((none.single as CogProblem).message, kCogNoServer);
    });

    test('passes on the server’s error message', () async {
      final c = CogClient(client: MockClient((_) async => http.Response('{"error":"Cog is not set up on this server yet"}', 503)));
      final ev = await c.chat('http://localhost:8080', {}).toList();
      expect((ev.single as CogProblem).message, contains('not set up'));
      expect(() => c.fix('http://localhost:8080', {}), throwsA(isA<CogFailure>()));
    });
  });

  group('Cog steps', () {
    test('explain → hint 1 → hint 2 → fix → Apply → quick check → learned', () async {
      final (s, fake) = await openProject();
      final cog = s.cog;
      await cog.explainError(s.problems.first);
      expect(cog.open, isTrue);
      expect(cog.items.map((i) => i.kind), [CogKind.you, CogKind.cog]);
      expect(fake.asked.last['task'], 'explain_error');
      expect(cog.canShowFix, isFalse, reason: 'Hints first: the fix waits for two hints');

      await cog.nextHint();
      await cog.nextHint();
      expect(fake.asked.last['task'], 'hint');
      expect(fake.asked.last['hint'], 2);
      expect(cog.items.where((i) => i.kind == CogKind.hint).map((i) => i.overline), ['Hint 1', 'Hint 2']);
      expect(cog.canShowFix, isTrue);
      final sent = fake.asked.last['messages'] as List;
      expect(sent.length, 5, reason: 'the conversation so far goes with each request');

      await cog.showFix();
      final fix = cog.items.lastWhere((i) => i.kind == CogKind.fix);
      expect(fix.fix!.file, 'Blink.ino');
      expect(s.cur!.files.first.content, contains('digitalwrite'), reason: 'nothing changes before Apply');

      await cog.applyFix(fix);
      expect(fix.fixState, 'applied');
      expect(s.cur!.files.first.content, contains('digitalWrite'));
      expect(s.problems, isEmpty);

      final q = cog.items.lastWhere((i) => i.kind == CogKind.check);
      expect(q.check!.question, 'Which compiles?');
      cog.answer(q, 1);
      expect(s.cur!.learned, isEmpty, reason: 'a wrong answer teaches nothing yet');
      cog.retry(q);
      cog.answer(q, 0);
      expect(s.cur!.learned, ['Names are case-sensitive']);
    });

    test('in "Explain the answer" the fix is offered straight away', () async {
      final (s, _) = await openProject();
      s.updateSettings((x) => x.cogStyle = 'explain');
      await s.cog.explainError(s.problems.first);
      expect(s.cog.canShowFix, isTrue);
      expect(s.cog.prompts.map((p) => p.$1), contains('Show the fix'));
    });

    test('Cog sends the project only when it may read it', () async {
      final (s, fake) = await openProject();
      await s.cog.ask('What does my code do?');
      final ctx = fake.asked.last['context'] as Map;
      expect(ctx['read'], isTrue);
      expect((ctx['files'] as List).first['content'], contains('digitalwrite'));
      expect((ctx['problems'] as List).single['line'], 2);
      expect(fake.asked.last['style'], 'hints');

      s.updateSettings((x) => x.cogRead = false);
      await s.cog.ask('And now?');
      expect(fake.asked.last['context'], {'read': false});
    });

    test('a selected block is explained with its C++ and its idea is learned', () async {
      final (s, fake) = await openProject();
      s.setMode('blocks');
      s.cog.selectBlock(const CogBlock(type: 'rc_forever', label: 'forever', cpp: 'void loop() {\n}'));
      expect(s.cog.prompts.first.$1, 'Explain forever');
      await s.cog.explainBlock();
      expect(fake.asked.last['task'], 'explain_block');
      expect((fake.asked.last['context'] as Map)['block'], {'label': 'forever', 'cpp': 'void loop() {\n}'});
      expect(s.cur!.learned, ['Loops']);
      await s.cog.challenge();
      expect(s.cog.items.last.kind, CogKind.tryIt);
      expect(s.cog.prompts.map((p) => p.$1), contains('I tried it'));
      await s.cog.triedIt();
      expect(fake.asked.last['task'], 'review_try');
    });

    test('an offline server shows the offline note', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(usbLink: FakeUsb(), cogClient: CogClient(client: MockClient((_) => Future.error(Exception('down')))));
      await s.load();
      s.updateSettings((x) => x.compileServer = 'http://localhost:8080');
      s.openExample(kExamples.first.id);
      await s.cog.ask('Hello?');
      expect(s.cog.items.last.kind, CogKind.notice);
      expect(s.cog.items.last.offline, isTrue);
      expect(s.cog.busy, isFalse);
    });
  });

  test('Cog settings and learned concepts are saved', () {
    final st = Settings.fromJson((Settings()
          ..cogStyle = 'explain'
          ..cogRead = false
          ..cogPin = cogPinHash('2468'))
        .toJson());
    expect(st.cogStyle, 'explain');
    expect(st.cogRead, isFalse);
    expect(st.cogPin, cogPinHash('2468'));
    expect(cogPinHash('2468'), isNot(cogPinHash('2469')));
    expect(Settings.fromJson({'cogStyle': 'nonsense'}).cogStyle, 'hints');
    final p = projectFrom(kExamples.first)..learned.add('Loops');
    expect(Project.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>).learned, ['Loops']);
  });

  test('the suggested fix shows only the changed lines, with one line around them', () {
    const before = 'a\nb\nc\nd\ne\nf\ng';
    const after = 'a\nb\nc\nD\ne\nf\ng';
    expect(cogDiff(before, after), [(' ', 3, 'c'), ('−', 0, 'd'), ('+', 4, 'D'), (' ', 5, 'e')]);
  });
}
