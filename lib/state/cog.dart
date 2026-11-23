// Cog in the IDE: the conversation, the hint ladder for an error (explain → hint 1 → another hint →
// show the fix → Apply → quick check), and the block steps (explain a block → Try it → I tried it).
// Cog guides before it fixes: it never changes code without Apply. AppState owns one CogController.
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../data/catalog.dart';
import '../engine/block_script.dart';
import '../engine/compiler.dart' show Problem;
import '../hw/cog_client.dart';
import '../ui/editor/block_picture.dart';
import 'app_state.dart';

enum CogKind { you, cog, hint, tryIt, fix, check, notice }

class CogItem {
  CogItem(this.kind, {this.text = '', this.overline, this.streaming = false, this.fix, this.check, this.offline = false, this.give = false});
  final CogKind kind;
  String text;
  final String? overline;

  /// Cog may hand this reply's blocks or code over (Add to my blocks, Insert in my code): the help style was
  /// Explain the answer or Write code for me, or the student asked for the fix. In Hints first it only guides.
  final bool give;

  /// Still arriving (a reply), or still being prepared (a fix or a question).
  bool streaming;
  CogFix? fix;

  /// The file as it was when the fix was suggested, so the diff still shows after Apply.
  String? before;
  String fixState = 'open'; // open | applied | dismissed
  CogCheck? check;
  int? picked;
  bool answered = false;
  final bool offline;
}

/// The block selected in Blockly: its type, how it reads, and the C++ it makes.
class CogBlock {
  const CogBlock({required this.type, required this.label, required this.cpp});
  final String type, label, cpp;
}

/// Set by the editor page while it is open (the editors are its children): Cog's blocks go loose beside the
/// program (a JSON list of Blockly block states), its code to the cursor. Null where the editors can't take them.
void Function(String json)? cogAddBlocks;
void Function(String text)? cogInsertCode;

/// Also set by the editor page: draws stacks of blocks (the same JSON) with the editor's own Blockly, so Cog's stacks
/// look exactly like the blocks in the editor; [ratio] is image pixels per logical pixel. Null without the web editors.
Future<BlockPicture?> Function(String json, double ratio)? cogPictureBlocks;

const kCogStyles = {'hints': 'Hints first', 'explain': 'Explain the answer', 'write': 'Write code for me'};

/// The teacher PIN as kept in Settings. A classroom lock that stops a change by accident, not a
/// security feature: anyone who clears the browser's site data removes it.
String cogPinHash(String pin) {
  var h = 0x811c9dc5;
  for (final u in 'robocore-cog:${pin.trim()}'.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// The idea each block teaches, for "You’ve learned".
const kBlockConcepts = {
  'rc_on_start': 'Setup', 'rc_forever': 'Loops', 'controls_repeat_ext': 'Loops', 'controls_whileUntil': 'Loops',
  'rc_wait': 'Delays', 'rc_led': 'LED output', 'rc_rgb': 'RGB colours', 'rc_pin': 'Digital pins', 'rc_tone': 'Sound',
  'controls_if': 'If / else', 'logic_compare': 'Comparisons', 'logic_operation': 'And / or', 'logic_negate': 'And / or',
  'logic_boolean': 'True / false', 'variables_set': 'Variables', 'variables_get': 'Variables', 'math_change': 'Variables',
  'math_number': 'Numbers', 'math_arithmetic': 'Maths', 'math_random_int': 'Random numbers', 'rc_drive': 'Motors',
  'rc_stop': 'Motors', 'rc_distance': 'Distance sensor', 'rc_print_distance': 'Distance sensor', 'rc_line': 'Line sensor',
  'rc_print_line': 'Line sensor', 'rc_user_pressed': 'Buttons', 'rc_wait_button': 'Buttons', 'rc_serial_begin': 'Serial Monitor',
  'rc_print_text': 'Serial Monitor', 'rc_print': 'Serial Monitor', 'text': 'Serial Monitor',
};

/// The order concepts usually come in; the first one not learned yet is shown as "next".
const kConceptPath = [
  'LED output', 'Delays', 'Loops', 'Sound', 'Serial Monitor', 'If / else', 'Buttons', 'Variables', 'Comparisons',
  'Motors', 'Distance sensor', 'Line sensor',
];

class CogController {
  CogController(this.app, {CogClient? client}) : client = client ?? CogClient();
  final AppState app;
  final CogClient client;

  bool open = false;
  bool busy = false;
  final items = <CogItem>[];
  final _history = <Map<String, String>>[]; // what was said, sent with the next request

  /// The error being worked on (the hint ladder), how many hints were given, whether the fix was shown.
  Problem? problem;
  int hints = 0;
  bool fixShown = false;

  CogBlock? block;
  bool challengeOpen = false;
  StreamSubscription<CogEvent>? _sub;

  String get styleLabel => kCogStyles[app.settings.cogStyle] ?? 'Hints first';
  /// Where Cog answers: RoboCore's own Cog, unless Settings → Cog names another server (a school's own).
  String get server => app.settings.cogServer.trim().isEmpty ? kCogServer : app.settings.cogServer.trim();
  String get _server => server;
  String get _key => app.settings.cogKey;

  /// This copy of the app's random number, made and kept the first time Cog is asked (Settings.cogDevice).
  String _device() {
    if (app.settings.cogDevice.isNotEmpty) return app.settings.cogDevice;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    app.updateSettings((x) => x.cogDevice = id);
    return id;
  }

  /// Who answers on the Cog server, as it last said (kept between runs). The notice and the captions say this.
  CogBy get by => CogBy.fromJson(app.settings.cogBy);

  /// Who the notice named when this device said OK.
  String get _seenBy => app.settings.cogNoticeFor.isEmpty ? CogBy.claude.id : app.settings.cogNoticeFor;

  /// The notice comes first: on a new device, and again when the server's AI is not the one it named.
  bool get needsNotice => !app.settings.cogNoticeSeen || _seenBy != by.id;

  String? _askedWho; // the server that was asked who answers, this run

  /// Asks the server who answers (once per server and run, or again with [force]) and keeps it.
  Future<void> refreshBy({bool force = false}) async {
    final server = _server;
    if (!force && _askedWho == server) return;
    _askedWho = server;
    final who = await client.who(server);
    if (who == null) {
      if (_askedWho == server) _askedWho = null; // not reached: ask again next time
      return;
    }
    if (who.id != by.id) app.updateSettings((x) => x.cogBy = who.id == CogBy.claude.id ? null : who.toJson());
  }

  void toggle() {
    if (!open && _off()) return;
    open = !open;
    if (open) unawaited(refreshBy());
    app.changed();
  }

  /// Turned off in Settings (a teacher can lock it with the PIN): Cog stays closed.
  bool _off() {
    if (app.settings.cogOn) return false;
    app.showToast('Cog is turned off', body: 'It can be turned on in Settings → Cog.', info: true);
    return true;
  }

  /// Nothing goes to Cog until this device was told what is sent and where: the panel opens on that notice
  /// (CogPanel), and the student asks again after reading it.
  bool _blocked() {
    if (_off()) return true;
    if (!needsNotice) return false;
    open = true;
    unawaited(refreshBy());
    app.changed();
    return true;
  }

  /// "OK" on the notice: it named [by].
  void noticeSeen() {
    final id = by.id;
    app.updateSettings((x) {
      x.cogNoticeSeen = true;
      x.cogNoticeFor = id;
    });
  }

  /// The server said its AI is not the one the notice named: ask who it is now, so the notice shows again.
  void _changed() => unawaited(refreshBy(force: true));

  void close() {
    open = false;
    app.changed();
  }

  /// Clears the conversation (the project and what was learned stay).
  void newChat({bool notify = true}) {
    _sub?.cancel();
    _sub = null;
    items.clear();
    _history.clear();
    problem = null;
    hints = 0;
    fixShown = false;
    challengeOpen = false;
    busy = false;
    if (notify) app.changed();
  }

  void selectBlock(CogBlock? b) {
    if (b?.type == block?.type && b?.label == block?.label && b?.cpp == block?.cpp) return;
    block = b;
    app.changed();
  }

  /// What Cog may read, sent with every request. Nothing from the project when reading is off.
  Map<String, Object?> context() {
    final p = app.cur;
    // Which editor is open is not the project's content: Cog needs it to answer with blocks or with code.
    if (p == null || !app.settings.cogRead) return {'read': false, if (p != null) 'editor': p.mode};
    String tail(Iterable<String> lines) {
      final l = lines.toList();
      return (l.length > 40 ? l.sublist(l.length - 40) : l).join('\n');
    }

    return {
      'read': true,
      'project': p.name,
      'board': kBoards[p.board]?.full ?? p.board,
      'editor': p.mode,
      'files': [
        for (final f in p.files) {'name': f.name, 'content': f.content}
      ],
      'problems': [
        for (final e in app.problems) {'file': e.file, 'line': e.line, 'column': e.column, 'severity': e.severity, 'message': e.msg}
      ],
      'output': tail(app.output.map((o) => o.text)),
      'serial': tail(app.log.map((l) => l.text)),
      if (p.mode == 'blocks' && block != null) 'block': {'label': block!.label, 'cpp': block!.cpp},
    };
  }

  Map<String, Object?> _body(String task, {int hint = 1, String? extra}) => {
        // Who the notice named: the server only answers when that is still its AI.
        'by': _seenBy,
        'style': app.settings.cogStyle,
        'level': app.settings.cogLevel,
        'task': task,
        'hint': hint,
        'messages': [
          ..._history,
          if (extra != null) {'role': 'user', 'content': extra},
        ],
        'context': context(),
      };

  void _remember(String role, String content) {
    if (content.trim().isEmpty) return;
    _history.add({'role': role, 'content': content});
    while (_history.length > 20) {
      _history.removeAt(0);
    }
  }

  void _notice(String text, {bool offline = false}) => items.add(CogItem(CogKind.notice, text: text, offline: offline));

  /// Sends one turn and streams the reply into a new item of kind [into].
  /// [you]: shown as the student's bubble; [said]: what is sent when nothing is shown.
  Future<void> _send(String task, {String? you, String? said, int hint = 1, CogKind into = CogKind.cog, String? overline, bool? give}) {
    if (busy || _blocked()) return Future.value();
    open = true;
    if (you != null) items.add(CogItem(CogKind.you, text: you));
    _remember('user', you ?? said ?? '');
    final reply = CogItem(into, overline: overline, streaming: true, give: give ?? app.settings.cogStyle != 'hints');
    items.add(reply);
    busy = true;
    app.changed();
    final done = Completer<void>();
    void finish() {
      if (done.isCompleted) return;
      reply.streaming = false;
      busy = false;
      if (reply.text.trim().isEmpty) {
        items.remove(reply);
      } else {
        _remember('assistant', reply.text);
      }
      app.changed();
      done.complete();
    }

    _sub = client.chat(_server, _body(task, hint: hint), key: _key, device: _device()).listen((e) {
      switch (e) {
        case CogText(:final text):
          reply.text += text;
          app.changed();
        case CogDone():
          finish();
        case CogProblem(:final message, :final offline, :final changed):
          if (reply.text.trim().isEmpty) items.remove(reply);
          _notice(message, offline: offline);
          if (changed) _changed();
          finish();
      }
    }, onDone: finish, onError: (_) {
      _notice('Cog hit a problem. Try again.');
      finish();
    });
    return done.future;
  }

  /// A question typed in the composer, or a prompt chip.
  Future<void> ask(String text) => text.trim().isEmpty ? Future.value() : _send('chat', you: text.trim());

  /// "Explain" on a problem (Problems, Output, or Explain with Cog in the code): starts the hint ladder.
  Future<void> explainError(Problem p) {
    if (busy || _blocked()) return Future.value();
    newChat(notify: false);
    problem = p;
    return _send('explain_error', you: 'Explain this error');
  }

  Future<void> nextHint() {
    if (problem == null || busy) return Future.value();
    hints++;
    return _send('hint', said: 'Give me hint $hints', hint: hints, into: CogKind.hint, overline: 'Hint $hints');
  }

  /// In "Hints first" the fix waits until two hints were given.
  bool get canShowFix => problem != null && !fixShown && (app.settings.cogStyle != 'hints' || hints >= 2);

  Future<void> showFix() async {
    if (busy || _blocked()) return;
    if (app.cur?.mode == 'blocks') {
      // In the blocks the fix is a stack to add, not a changed file (applying a file would leave the blocks behind).
      fixShown = true;
      final p = problem;
      return _send('fix_blocks', said: p == null ? 'Show me the fix.' : 'Show me the fix for: ${p.file}:${p.line} ${p.msg}', give: true);
    }
    fixShown = true;
    final item = CogItem(CogKind.fix, streaming: true);
    items.add(item);
    busy = true;
    open = true;
    app.changed();
    final ask = problem == null
        ? 'Show me the fix.'
        : 'Show me the fix for: ${problem!.file}:${problem!.line} ${problem!.msg}';
    try {
      final f = await client.fix(_server, _body('chat', extra: ask), key: _key, device: _device());
      item.before = app.cur?.files.where((x) => x.name == f.file).firstOrNull?.content;
      item.fix = f;
      item.streaming = false;
      // Cog didn't say this in a reply, so it goes in as a note from the IDE, not as Cog's words.
      _remember('user', '$ask\n\n[RoboCore IDE: Cog suggested a change to ${f.file}: ${f.explanation}]');
    } on CogFailure catch (e) {
      items.remove(item);
      fixShown = false;
      _notice(e.message, offline: e.offline);
      if (e.changed) _changed();
    }
    busy = false;
    app.changed();
  }

  // ---------- blocks and code from a reply into the project

  /// Whether a reply's blocks can go into the workspace now, and its code into the sketch.
  bool get canAddBlocks => cogAddBlocks != null && app.cur?.mode == 'blocks';
  bool get canInsertCode => cogInsertCode != null && app.cur?.mode == 'code';

  String? _varsOf;
  List<String> _vars = const [];

  /// A blocks script from a reply, read with the project's variables.
  BlockScript blocksOf(String script) {
    final saved = app.cur?.blockly;
    if (saved != _varsOf) {
      _varsOf = saved;
      try {
        _vars = saved == null ? const [] : blocklyVariables((jsonDecode(saved) as Map).cast<String, dynamic>());
      } catch (_) {
        _vars = const [];
      }
    }
    return parseBlockScript(script, variables: _vars);
  }

  final _pictures = <String, Future<BlockPicture?>>{};

  /// A picture of [script]'s stacks drawn by the editor's Blockly, or null when there is none to draw them (the panel
  /// then draws the stack itself). Each stack is drawn once per theme and pixel ratio.
  Future<BlockPicture?>? pictureOf(BlockScript script, {required bool dark, required double ratio}) {
    final draw = cogPictureBlocks;
    if (draw == null || script.isEmpty) return null;
    final json = jsonEncode(script.stacks);
    final key = '$dark $ratio $json';
    final known = _pictures[key];
    if (known != null) return known;
    if (_pictures.length >= 40) _pictures.remove(_pictures.keys.first);
    return _pictures[key] = draw(json, ratio);
  }

  /// Puts a reply's blocks loose beside the program (one undo step). The student joins them on.
  void addBlocks(BlockScript script) {
    final add = cogAddBlocks;
    if (add == null || script.isEmpty || app.cur?.mode != 'blocks') return;
    add(jsonEncode(script.stacks));
    final left = script.unknown;
    app.showToast('Blocks added beside your program',
        body: left == 0
            ? 'Drag them into place. Undo takes them away again.'
            : 'Drag them into place. $left line${left == 1 ? ' is' : 's are'} not a block: build ${left == 1 ? 'it' : 'them'} yourself.');
  }

  /// Puts a reply's code at the cursor in the code editor (one undo step).
  void insertCode(String code) {
    final insert = cogInsertCode;
    if (insert == null || code.trim().isEmpty || app.cur?.mode != 'code') return;
    insert(code);
    app.showToast('Code put in at the cursor', body: 'Undo takes it out again.');
  }

  Future<void> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      app.showToast('Copied');
    } catch (_) {
      app.showToast('Could not copy', body: 'Select the text and copy it yourself.', error: true);
    }
  }

  /// Applies the suggested fix (one undo step in the code editor), then asks one quick-check question.
  Future<void> applyFix(CogItem it) async {
    final f = it.fix;
    if (f == null || it.fixState != 'open') return;
    app.applyFile(f.file, f.newContent);
    it.fixState = 'applied';
    app.changed();
    await _quickCheck();
  }

  void dismissFix(CogItem it) {
    it.fixState = 'dismissed';
    fixShown = false;
    app.changed();
  }

  Future<void> _quickCheck() async {
    if (busy || _blocked()) return;
    final item = CogItem(CogKind.check, streaming: true);
    items.add(item);
    busy = true;
    app.changed();
    try {
      item.check = await client.check(_server, _body('chat', extra: 'I applied the fix.'), key: _key, device: _device());
      item.streaming = false;
    } on CogFailure catch (e) {
      items.remove(item); // the question is a bonus: no notice when it can't be made
      if (e.changed) _changed();
    }
    busy = false;
    app.changed();
  }

  void answer(CogItem it, int option) {
    final q = it.check;
    if (q == null || it.answered) return;
    it.picked = option;
    it.answered = true;
    if (option == q.answer) app.learn(q.concept);
    app.changed();
  }

  /// Lets the student try the question again after a wrong answer.
  void retry(CogItem it) {
    it.answered = false;
    it.picked = null;
    app.changed();
  }

  Future<void> explainBlock() async {
    final b = block;
    if (b == null) return ask('Explain my blocks.');
    await _send('explain_block', you: 'What does ${b.label} do?');
    final concept = kBlockConcepts[b.type];
    if (concept != null) app.learn(concept);
  }

  Future<void> challenge() async {
    await _send('challenge', said: 'Give me a challenge', into: CogKind.tryIt, overline: 'Try it');
    challengeOpen = items.isNotEmpty && items.last.kind == CogKind.tryIt;
    app.changed();
  }

  Future<void> triedIt() {
    challengeOpen = false;
    return _send('review_try', you: 'I tried it');
  }

  /// The next steps offered under the conversation (prompt chips).
  List<(String, Future<void> Function())> get prompts {
    if (problem != null) {
      return [
        if (!fixShown && hints < 3) (hints == 0 ? 'Give me a hint' : 'Another hint', nextHint),
        if (canShowFix) ('Show the fix', showFix),
        ('What should I try next?', () => ask('What should I try next?')),
        if (app.cur?.mode == 'blocks' && block != null) ('Explain ${block!.label}', explainBlock),
      ];
    }
    final p = app.cur;
    if (p != null && p.mode == 'blocks') {
      return [
        if (block != null) ('Explain ${block!.label}', explainBlock),
        if (challengeOpen) ('I tried it', triedIt) else ('Give me a challenge', challenge),
      ];
    }
    return [
      ('Explain my code', () => ask('Explain what my code does.')),
      ('Why doesn’t it work?', () => ask('Why doesn’t my sketch work?')),
      if (challengeOpen) ('I tried it', triedIt) else ('Give me a challenge', challenge),
    ];
  }

  /// The concept to learn next, after what is already learned.
  String? get nextConcept {
    final learned = {for (final x in app.cur?.learned ?? const <String>[]) x.toLowerCase()};
    for (final c in kConceptPath) {
      if (!learned.contains(c.toLowerCase())) return c;
    }
    return null;
  }
}
