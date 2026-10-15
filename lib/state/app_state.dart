// All app state: projects, settings, the editor session, the serial log,
// and the build / upload flow. Persisted with shared_preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart';
import '../engine/compiler.dart';
import 'models.dart';
import 'sim_board.dart';

enum View { home, projects, examples, libraries, board, serial, settings, editor }

class Verified {
  final int size, pct, rp;
  const Verified(this.size, this.pct, this.rp);
}

class ConnMsg {
  final String kind, text; // '' | ok | err
  const ConnMsg(this.kind, this.text);
}

const _storeKey = 'robocore-ide-v1';

class AppState extends ChangeNotifier {
  AppState() {
    sim = SimBoard(
      onSerial: (t, d) => serialPush(t, d),
      onNote: (t) {
        outLine(t, 'sys');
        notifyListeners();
      },
    );
  }

  late final SimBoard sim;
  SharedPreferences? _prefs;
  Timer? _persistTimer;
  Timer? _saveTimer;
  final _rnd = math.Random();

  // ---- persisted ----
  String user = 'Fredrick';
  String board = 'v2';
  String port = kPort;
  int baud = 115200;
  bool connected = true;
  String cpu = '240 MHz';
  String partition = '8 MB · 3 MB app / 1.5 MB SPIFFS';
  Settings settings = Settings();
  Map<String, bool> libs = {'esp32servo': true, 'neopixel': true, 'newping': false, 'lcd': false};
  List<Project> projects = [];

  // ---- session ----
  View view = View.home;
  String? pid;
  int file = 0;
  final List<int> closedTabs = [];
  String target = 'loop';
  bool panelOpen = true;
  String panelTab = 'serial';
  String cat = 'output';
  double zoom = 1;
  final List<String> _past = [], _future = [];
  bool sideCollapsed = false;
  String ptab = 'all', pfilter = '', excat = 'All', exq = '', libq = '';
  String? bsel;
  String stateLabel = 'Ready', stateKind = '';
  String? busy;
  final List<OutLine> output = [];
  List<Problem> problems = [];
  Verified? verified;
  final List<LogLine> log = [];
  bool timestamps = true, autoscroll = true;
  String lineEnd = 'nl';
  final Map<String, String> installing = {};
  ConnMsg? conn;
  String saveState = 'saved';
  CompileResult? lastRun;
  String? lastRunName;
  String cursorPos = 'Ln 1, Col 1';
  String? toast;
  Timer? _toastTimer;
  int logVersion = 0;

  /// Bumped on every serial line, so only log views rebuild.
  final ValueNotifier<int> logTick = ValueNotifier(0);

  Project? get cur {
    for (final p in projects) {
      if (p.id == pid) return p;
    }
    return null;
  }

  List<Project> get sortedProjects => [...projects]..sort((a, b) => b.updated.compareTo(a.updated));
  String get boardId => (view == View.editor && cur != null) ? cur!.board : board;
  Set<String> get installedLibs => {for (final e in libs.entries) if (e.value) e.key};

  // ---------- persistence ----------
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_storeKey);
      if (raw != null) {
        final o = jsonDecode(raw) as Map<String, dynamic>;
        if (o['v'] == 1 && o['projects'] is List) {
          user = o['user'] as String? ?? user;
          board = o['board'] as String? ?? board;
          port = o['port'] as String? ?? port;
          baud = (o['baud'] as num?)?.toInt() ?? baud;
          connected = o['connected'] as bool? ?? connected;
          cpu = o['cpu'] as String? ?? cpu;
          partition = o['partition'] as String? ?? partition;
          settings = Settings.fromJson(((o['settings'] as Map?) ?? const {}).cast<String, dynamic>());
          libs = {...libs, ...((o['libs'] as Map?) ?? const {}).cast<String, bool>()};
          projects = [for (final p in o['projects'] as List) Project.fromJson((p as Map).cast<String, dynamic>())];
          sideCollapsed = _prefs!.getBool('rc-side') ?? false;
        }
      }
    } catch (_) {
      projects = [];
    }
    if (projects.isEmpty) _seed();
    serialPush('Connected to $port at $baud baud', 'sys');
    _bootBoard();
    notifyListeners();
  }

  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    const m = 60000, h = 3600000, d = 86400000;
    projects = [
      projectFrom(exampleById('blink'), updated: now - 2 * m),
      projectFrom(exampleById('obstacle'), updated: now - 2 * h),
      projectFrom(exampleById('traffic'), board: 'uno', mode: 'blocks', updated: now - 26 * h),
      projectFrom(exampleById('line'), mode: 'blocks', updated: now - 3 * d),
      projectFrom(exampleById('melody'), board: 'uno', mode: 'code', updated: now - 8 * d),
      projectFrom(exampleById('servo'), board: 'devkit', updated: now - 15 * d),
      projectFrom(exampleById('distance'), updated: now - 22 * d),
      projectFrom(exampleById('logger'), board: 'nodemcu', updated: now - 33 * d),
    ];
    persist(now: true);
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'user': user,
        'board': board,
        'port': port,
        'baud': baud,
        'connected': connected,
        'cpu': cpu,
        'partition': partition,
        'settings': settings.toJson(),
        'libs': libs,
        'projects': projects.map((p) => p.toJson()).toList(),
      };

  void persist({bool now = false}) {
    _persistTimer?.cancel();
    void w() {
      try {
        _prefs?.setString(_storeKey, jsonEncode(toJson()));
      } catch (_) {}
    }

    if (now) {
      w();
    } else {
      _persistTimer = Timer(const Duration(milliseconds: 400), w);
    }
  }

  void showToast(String msg) {
    toast = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void setStatus(String label, [String kind = '']) {
    stateLabel = label;
    stateKind = kind;
  }

  // ---------- navigation ----------
  void go(View v) {
    view = v;
    if (v != View.board) conn = null;
    if (v == View.board) bsel = null;
    if (v == View.editor && cur == null) {
      final s = sortedProjects;
      if (s.isEmpty) {
        view = View.home;
      } else {
        pid = s.first.id;
      }
    }
    setStatus(sim.running ? 'Running' : 'Ready');
    notifyListeners();
  }

  void toggleSidebar() {
    sideCollapsed = !sideCollapsed;
    _prefs?.setBool('rc-side', sideCollapsed);
    notifyListeners();
  }

  void openProject(String id) {
    final p = projects.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    closedTabs.clear();
    if (pid != id) {
      problems = [];
      verified = null;
      file = 0;
      target = 'loop';
      _past.clear();
      _future.clear();
    }
    pid = id;
    p.syncCode();
    go(View.editor);
  }

  void openExample(String id) {
    final ex = exampleById(id);
    var name = ex.proj;
    var n = 2;
    while (projects.any((p) => p.name == name)) {
      name = '${ex.proj} ${n++}';
    }
    final p = projectFrom(ex, name: name, board: board);
    p.autosave = settings.autosave;
    projects.add(p);
    persist(now: true);
    showToast('Copied “${ex.name}” into your projects as $name.');
    openProject(p.id);
  }

  String? validateName(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'Give your project a name.';
    if (!RegExp(r'^[A-Za-z0-9 ]+$').hasMatch(t)) return 'Use only letters, numbers and spaces.';
    return null;
  }

  void createProject({required String name, required String mode, required String boardId}) {
    final nm = name.trim();
    final ex = Example(
      id: 'new',
      name: nm,
      proj: nm,
      cat: '',
      level: '',
      desc: '',
      tag: '',
      boards: '',
      blocks: mode == 'blocks' ? const {'setup': [], 'loop': []} : null,
      code: '// $nm\n\nvoid setup() {\n  // runs once\n}\n\nvoid loop() {\n  // runs over and over\n}\n',
    );
    final p = projectFrom(ex, name: nm, board: boardId, mode: mode);
    p.files.first.name = '${fileBase(nm)}.ino';
    p.autosave = settings.autosave;
    projects.add(p);
    persist(now: true);
    openProject(p.id);
  }

  void saveProjectSettings(Project p, {required String name, required String boardId, required bool autosave}) {
    if (boardId != p.board) {
      verified = null;
      problems = [];
    }
    p.name = name.trim();
    p.board = boardId;
    p.autosave = autosave;
    if (autosave) p.dirty = false;
    saveNow(p);
    touch(p, immediate: true);
    showToast('Project settings saved.');
  }

  void deleteProject(Project p) {
    final name = p.name;
    projects.remove(p);
    persist(now: true);
    sim.stop();
    pid = null;
    showToast('Deleted $name.');
    go(View.projects);
  }

  // ---------- saving ----------
  void touch(Project p, {bool immediate = false}) {
    p.updated = DateTime.now().millisecondsSinceEpoch;
    if (!p.codeEdited && p.mode == 'blocks') p.files.first.content = p.generate();
    if (p.autosave) {
      saveState = 'saving';
      p.dirty = false;
      _saveTimer?.cancel();
      _saveTimer = Timer(Duration(milliseconds: immediate ? 0 : 600), () {
        persist(now: true);
        saveState = 'saved';
        notifyListeners();
      });
    } else {
      p.dirty = true;
    }
    notifyListeners();
  }

  void saveNow(Project p) {
    p.dirty = false;
    p.updated = DateTime.now().millisecondsSinceEpoch;
    persist(now: true);
    saveState = 'saved';
    notifyListeners();
  }

  (String, String) saveLabel(Project p) {
    if (!p.autosave && p.dirty) return ('dirty', 'Unsaved changes');
    if (saveState == 'saving') return ('saving', 'Saving…');
    return ('saved', 'Saved');
  }

  // ---------- board / connection ----------
  void pickBoard(String id) {
    final p = cur;
    if (view == View.editor && p != null) {
      p.board = id;
      verified = null;
      problems = [];
      touch(p, immediate: true);
    } else {
      board = id;
      persist(now: true);
    }
    showToast('Board set to ${kBoards[id]!.name}.');
  }

  void setDefaultBoard(String id) {
    board = id;
    bsel = null;
    persist(now: true);
    showToast('${kBoards[id]!.name} is now your default board.');
  }

  void selectBoardDetail(String id) {
    bsel = id;
    conn = null;
    notifyListeners();
  }

  void testConnection() {
    conn = const ConnMsg('', 'Testing…');
    notifyListeners();
    Timer(const Duration(milliseconds: 700), () {
      conn = connected && port == kPort
          ? ConnMsg('ok', '${kBoards[board]!.name} answered on $port in ${8 + _rnd.nextInt(10)} ms.')
          : ConnMsg('err', connected ? 'No board answered on $port. Pick the usbmodem port.' : 'The board is disconnected. Press Connect first.');
      notifyListeners();
    });
  }

  void disconnect() {
    connected = false;
    sim.stop();
    persist(now: true);
    serialPush('Disconnected from $port.', 'sys');
    conn = null;
    notifyListeners();
  }

  void connect() {
    connected = true;
    persist(now: true);
    serialPush('Connected to $port at $baud baud', 'sys');
    conn = ConnMsg('ok', 'Connected to $port.');
    notifyListeners();
  }

  void setPort(String v, {bool fromMenu = false}) {
    port = v;
    persist(now: true);
    conn = null;
    serialPush(v == kPort ? 'Connected to $port at $baud baud' : 'No board on $v. Choose the usbmodem port.', v == kPort ? 'sys' : 'err');
    notifyListeners();
  }

  void setBaud(int v) {
    baud = v;
    persist(now: true);
    serialPush('Baud rate set to $baud.', 'sys');
    if (baud != 115200 && sim.running) serialPush('The sketch prints at 115200 baud, so text may look garbled at this rate.', 'err');
    notifyListeners();
  }

  void setCpu(String v) {
    cpu = v;
    persist(now: true);
    notifyListeners();
  }

  void setPartition(String v) {
    partition = v;
    persist(now: true);
    notifyListeners();
  }

  // ---------- libraries ----------
  void install(String id) {
    final l = kLibs.firstWhere((x) => x.id == id);
    installing[id] = 'Installing…';
    notifyListeners();
    Timer(const Duration(milliseconds: 1100), () {
      installing.remove(id);
      libs[id] = true;
      persist(now: true);
      showToast('${l.name} ${l.ver} installed.');
    });
  }

  void uninstall(String id) {
    libs[id] = false;
    persist(now: true);
    showToast('${kLibs.firstWhere((x) => x.id == id).name} removed.');
  }

  // ---------- settings ----------
  void updateSettings(void Function(Settings s) f) {
    f(settings);
    persist(now: true);
    notifyListeners();
  }

  // ---------- serial ----------
  void serialPush(String text, [String dir = 'out']) {
    log.add(LogLine(stamp(), text, dir));
    if (log.length > 1500) log.removeRange(0, log.length - 1200);
    logVersion++;
    logTick.value++;
  }

  void clearLog() {
    log.clear();
    logVersion++;
    logTick.value++;
    notifyListeners();
  }

  void sendSerial(String text) {
    if (!connected) {
      serialPush('Board not connected. Connect it in Board Setup.', 'err');
      return;
    }
    final end = const {'nl': '\n', 'none': '', 'cr': '\r', 'both': '\r\n'}[lineEnd] ?? '\n';
    serialPush(text, 'in');
    sim.queueInput(text + end);
    final b = kBoards[sim.running ? sim.boardId : boardId]!;
    if (text.trim().toLowerCase() == 'status' && b.id == 'v2') {
      Timer(const Duration(milliseconds: 120), () {
        if (!sim.readsSerial) {
          final up = sim.running ? sim.uptimeSeconds : 0;
          serialPush('ok · uptime $up s · battery 3.92 V', 'out');
        }
      });
    } else if (!sim.running) {
      Timer(const Duration(milliseconds: 80), () => serialPush('No sketch is running. Upload one to talk to the board.', 'sys'));
    }
  }

  // ---------- output ----------
  void outLine(String text, [String kind = '']) {
    final d = DateTime.now();
    output.add(OutLine('${clock(d)}:${two(d.second)}', text, kind));
    if (output.length > 400) output.removeAt(0);
  }

  void clearOutput() {
    output.clear();
    notifyListeners();
  }

  // ---------- build ----------
  Future<CompileResult?> verify({bool fromUpload = false}) async {
    final p = cur;
    if (p == null || busy != null) return null;
    p.syncCode();
    busy = 'verify';
    problems = [];
    verified = null;
    if (!fromUpload) output.clear();
    final b = kBoards[p.board]!;
    final sw = Stopwatch()..start();
    outLine('Compiling sketch for ${b.full}…', 'info');
    setStatus('Verifying…', 'busy');
    panelOpen = true;
    if (panelTab == 'problems' || !fromUpload) panelTab = 'output';
    notifyListeners();
    await Future<void>.delayed(Duration(milliseconds: 650 + _rnd.nextInt(450)));
    CompileResult r;
    try {
      r = compileSketch(
        files: [for (final f in p.files) SourceFile(f.name, f.content)],
        boardId: p.board,
        installedLibs: installedLibs,
      );
    } catch (e) {
      r = CompileResult(errors: [Problem(p.files.first.name, 1, 'Internal error while checking the sketch: $e')], board: b);
    }
    busy = null;
    if (r.errors.isNotEmpty) {
      problems = r.errors;
      for (final e in r.errors) {
        outLine('${e.file}:${e.line}: error: ${e.msg}', 'err');
      }
      outLine('Compilation failed with ${r.errors.length} error${r.errors.length > 1 ? 's' : ''}.', 'err');
      panelTab = 'problems';
      setStatus('Errors', 'err');
      notifyListeners();
      return null;
    }
    final pct = math.max(1, (r.size / b.max * 100).round());
    final rp = math.max(1, (r.ram / b.ram * 100).round());
    outLine('Sketch uses ${fmtN(r.size)} bytes ($pct%) of program storage space. Maximum is ${fmtN(b.max)} bytes.');
    outLine('Global variables use ${fmtN(r.ram)} bytes ($rp%) of dynamic memory.');
    outLine('Verified in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s — ready to upload', 'ok');
    verified = Verified(r.size, pct, rp);
    setStatus('Verified');
    notifyListeners();
    return r;
  }

  Future<void> upload() async {
    final p = cur;
    if (p == null || busy != null) return;
    if (!connected) {
      output.clear();
      outLine('Upload needs a connected board. Connect it in Board Setup, then try again.', 'err');
      panelTab = 'output';
      panelOpen = true;
      setStatus('Not connected', 'err');
      notifyListeners();
      return;
    }
    if (!p.autosave) saveNow(p);
    output.clear();
    final r = await verify(fromUpload: true);
    if (r == null) return;
    final b = r.board;
    busy = 'upload';
    setStatus('Uploading…', 'busy');
    outLine('Connecting to ${b.name} on $port…');
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 380));
    outLine('Chip is ${b.chip}. Writing ${fmtN(r.size)} bytes…');
    for (final pc in const [18, 46, 73, 100]) {
      final addr = (0x10000 + (r.size * pc / 100).round()).toRadixString(16).padLeft(8, '0');
      outLine('Writing at 0x$addr… ($pc %)');
      notifyListeners();
      await Future<void>.delayed(Duration(milliseconds: 170 + _rnd.nextInt(120)));
    }
    outLine('Hard resetting via RTS pin…');
    outLine('Uploaded to the preview ${b.name}. The sketch is now running in the simulator.', 'ok');
    busy = null;
    lastRun = r;
    lastRunName = p.name;
    serialPush('— ${b.name} reset —', 'sys');
    _bootBanner(b);
    setStatus('Running');
    notifyListeners();
    _run(r, p.name);
  }

  void _bootBanner(BoardDef b) {
    if (b.arch == 'esp32') {
      serialPush(b.id == 'v2' ? 'ESP-ROM:esp32s3-20210327' : 'ets Jul 29 2019 12:21:46', 'out');
      serialPush('rst:0x1 (POWERON),boot:0x8 (SPI_FAST_FLASH_BOOT)', 'out');
    }
  }

  Future<void> _run(CompileResult r, String name) async {
    final err = await sim.run(r, name);
    if (err != null) {
      final where = err.line != null ? ' (line ${err.line})' : '';
      serialPush('Sketch stopped: ${err.msg}$where', 'err');
      outLine('Runtime error${err.line != null ? ' on line ${err.line}' : ''}: ${err.msg}', 'err');
    }
    if (!sim.running) {
      setStatus('Stopped');
      notifyListeners();
    }
  }

  void stopSketch() {
    sim.stop();
    setStatus('Stopped');
    notifyListeners();
  }

  void rerun() {
    final r = lastRun;
    if (r == null) return;
    serialPush('— ${r.board.name} reset —', 'sys');
    setStatus('Running');
    notifyListeners();
    _run(r, lastRunName ?? '');
  }

  void _bootBoard() {
    if (!connected) return;
    final p = projects.where((x) => x.name == 'Blink LED').firstOrNull ?? sortedProjects.firstOrNull;
    if (p == null) return;
    p.syncCode();
    try {
      final r = compileSketch(
        files: [for (final f in p.files) SourceFile(f.name, f.content)],
        boardId: p.board,
        installedLibs: installedLibs,
      );
      if (r.errors.isNotEmpty) return;
      lastRun = r;
      lastRunName = p.name;
      _bootBanner(r.board);
      _run(r, p.name);
    } catch (_) {}
  }

  // ---------- editor ----------
  void setMode(String m) {
    final p = cur;
    if (p == null || p.mode == m) return;
    if (m == 'code') p.syncCode();
    p.mode = m;
    file = 0;
    touch(p, immediate: true);
  }

  void openFile(int i) {
    file = i;
    closedTabs.remove(i);
    notifyListeners();
  }

  void closeTab(int i) {
    final p = cur;
    if (p == null) return;
    if (!closedTabs.contains(i)) closedTabs.add(i);
    if (file == i) {
      final k = List.generate(p.files.length, (k) => k).where((k) => !closedTabs.contains(k));
      file = k.isEmpty ? 0 : k.first;
      if (k.isEmpty) closedTabs.clear();
    }
    notifyListeners();
  }

  void editCode(String text) {
    final p = cur;
    if (p == null) return;
    final f = p.files[file.clamp(0, p.files.length - 1).toInt()];
    if (f.content == text) return;
    f.content = text;
    if (file == 0 && !p.codeEdited) p.codeEdited = true;
    verified = null;
    touch(p);
  }

  void rebuildFromBlocks() {
    final p = cur;
    if (p == null) return;
    p.codeEdited = false;
    touch(p, immediate: true);
    showToast('Code rebuilt from the blocks.');
  }

  void gotoProblem(Problem pr) {
    final p = cur;
    if (p == null) return;
    final fi = p.files.indexWhere((f) => f.name == pr.file);
    if (p.mode != 'code') {
      p.mode = 'code';
      p.syncCode();
    }
    file = math.max(0, fi);
    closedTabs.remove(file);
    gotoLine = pr.line;
    notifyListeners();
  }

  /// Set by gotoProblem; the code editor consumes it to move the cursor.
  int? gotoLine;

  void setPanelTab(String t) {
    panelTab = t;
    panelOpen = true;
    notifyListeners();
  }

  void togglePanel() {
    panelOpen = !panelOpen;
    notifyListeners();
  }

  void setCat(String c) {
    cat = c;
    notifyListeners();
  }

  void setTarget(String s) {
    target = s;
    notifyListeners();
  }

  void setZoom(int dir) {
    zoom = dir == 0 ? 1.0 : ((zoom + dir * .15) * 100).round().clamp(55, 175) / 100;
    notifyListeners();
  }

  String _snapStr(Project p) => jsonEncode({'setup': p.setup, 'loop': p.loop});
  void _restore(Project p, String s) {
    final o = jsonDecode(s) as Map<String, dynamic>;
    p.setup = cloneBlocks(o['setup']);
    p.loop = cloneBlocks(o['loop']);
  }

  void snap() {
    final p = cur;
    if (p == null) return;
    _past.add(_snapStr(p));
    if (_past.length > 60) _past.removeAt(0);
    _future.clear();
  }

  void _afterBlocks(Project p) {
    verified = null;
    touch(p);
  }

  void addBlock(String t, {String? stack, int? index}) {
    final p = cur;
    if (p == null) return;
    snap();
    final s = stack ?? target;
    final list = p.stack(s);
    final b = <String, dynamic>{'t': t, ...kBlockTypes[t]!.def};
    list.insert((index ?? list.length).clamp(0, list.length).toInt(), b);
    target = s;
    _afterBlocks(p);
  }

  void removeBlock(String stack, int i) {
    final p = cur;
    if (p == null) return;
    snap();
    p.stack(stack).removeAt(i);
    _afterBlocks(p);
  }

  void moveBlock(String fromStack, int fromIndex, String toStack, int toIndex) {
    final p = cur;
    if (p == null) return;
    snap();
    final b = p.stack(fromStack).removeAt(fromIndex);
    var i = toIndex;
    if (fromStack == toStack && fromIndex < i) i--;
    final list = p.stack(toStack);
    list.insert(i.clamp(0, list.length).toInt(), b);
    target = toStack;
    _afterBlocks(p);
  }

  void setBlockField(String stack, int i, String k, dynamic v, {bool snapshot = true}) {
    final p = cur;
    if (p == null) return;
    final list = p.stack(stack);
    if (i < 0 || i >= list.length) return;
    if (snapshot) snap();
    list[i][k] = v;
    verified = null;
    touch(p);
  }

  void clearBlocks() {
    final p = cur;
    if (p == null) return;
    snap();
    p.setup = [];
    p.loop = [];
    _afterBlocks(p);
    showToast('All blocks removed. Press Undo to bring them back.');
  }

  void undo() {
    final p = cur;
    if (p == null) return;
    if (_past.isEmpty) return showToast('Nothing to undo.');
    _future.add(_snapStr(p));
    _restore(p, _past.removeLast());
    _afterBlocks(p);
  }

  void redo() {
    final p = cur;
    if (p == null) return;
    if (_future.isEmpty) return showToast('Nothing to redo.');
    _past.add(_snapStr(p));
    _restore(p, _future.removeLast());
    _afterBlocks(p);
  }

  void resetAll() {
    sim.stop();
    _seed();
    pid = null;
    lastRun = null;
    showToast('Sample projects restored.');
    go(View.home);
  }

  void setSerialOption({bool? ts, bool? scroll, String? ending}) {
    if (ts != null) timestamps = ts;
    if (scroll != null) autoscroll = scroll;
    if (ending != null) lineEnd = ending;
    notifyListeners();
  }

  void setFilter({String? ptab, String? pfilter, String? excat, String? exq, String? libq}) {
    if (ptab != null) this.ptab = ptab;
    if (pfilter != null) this.pfilter = pfilter;
    if (excat != null) this.excat = excat;
    if (exq != null) this.exq = exq;
    if (libq != null) this.libq = libq;
    notifyListeners();
  }

  void setCursor(String pos) {
    if (pos == cursorPos) return;
    cursorPos = pos;
    notifyListeners();
  }
}
