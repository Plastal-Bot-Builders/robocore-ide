// All app state: projects, settings, the editor session, the serial log,
// and the build / upload flow. Persisted with shared_preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart';
import '../engine/compiler.dart';
import '../engine/zip.dart';
import '../hw/cog_client.dart';
import '../hw/compile_client.dart';
import '../hw/download.dart';
import '../hw/usb_link.dart';
import 'cog.dart';
import 'models.dart';
import 'project_folder.dart';
import 'sim_board.dart';

enum Screen { home, projects, examples, libraries, board, serial, settings, editor }

class Verified {
  final int size, pct, rp;
  const Verified(this.size, this.pct, this.rp);
}

class ConnMsg {
  final String kind, text; // '' | ok | err
  const ConnMsg(this.kind, this.text);
}

const _storeKey = 'robocore-ide-v1';

/// Shown when esptool-js cannot put the board into its bootloader.
const kBootTip = 'Could not start the board’s bootloader. Hold BOOT, tap RESET, release BOOT, then press Upload again. '
    '(When the upload finishes, press RESET once to run the new sketch.)';

/// Shown when an Arduino Uno's bootloader does not answer.
const kAvrTip = 'Check that Board Setup is set to the board you plugged in, and close anything else using its port (the '
    'Arduino IDE’s Serial Monitor, another browser tab). Then press Upload again.';

class AppState extends ChangeNotifier {
  AppState({UsbLink? usbLink, CompileClient? compileClient, CogClient? cogClient})
      : usb = usbLink ?? createUsbLink(),
        compiler = compileClient ?? CompileClient() {
    cog = CogController(this, client: cogClient);
    sim = SimBoard(
      onSerial: (t, d) => serialPush(t, d),
      onNote: (t) {
        outLine(t, 'sys');
        notifyListeners();
      },
    );
    usb.onText = _onUsbText;
    usb.onEvent = _onUsbEvent;
  }

  late final SimBoard sim;

  /// Cog, the learning partner (state/cog.dart).
  late final CogController cog;

  /// For helpers that keep part of the app's state (Cog): tell the UI something changed.
  void changed() => notifyListeners();

  /// Replaces a file's content (Cog's Apply). The code editor makes it one undo step.
  void applyFile(String name, String content) {
    final p = cur;
    if (p == null) return;
    final i = p.files.indexWhere((f) => f.name == name);
    if (i < 0) return;
    p.files[i].content = content;
    if (i == 0 && !p.codeEdited) p.codeEdited = true;
    problems = [for (final e in problems) if (e.file != name) e];
    verified = null;
    if (p.mode != 'code') p.mode = 'code';
    file = i;
    closedTabs.remove(i);
    touch(p);
    showToast('Fix applied to $name', body: 'Press Ctrl+Z in the code to undo it.');
  }

  /// Adds a concept to the project's "You’ve learned" list.
  void learn(String concept) {
    final p = cur;
    final c = concept.trim();
    if (p == null || c.isEmpty || p.learned.any((x) => x.toLowerCase() == c.toLowerCase())) return;
    p.learned.add(c);
    touch(p);
  }

  /// The real board on USB (Web Serial on the web: esptool-js for an ESP32, Optiboot for an Uno).
  final UsbLink usb;

  /// The compile server client (arduino-cli in a container, see server/).
  final CompileClient compiler;

  /// The macOS app compiles on this Mac (arduino-cli inside the app) for the boards it can; the compile server
  /// builds the others, and everything in the web app.
  LocalBuilder? local;
  bool _buildsHere(Project p) => local?.canBuild(p.board) ?? false;
  SharedPreferences? _prefs;
  Timer? _persistTimer;
  Timer? _saveTimer;
  final _rnd = math.Random();

  // ---- persisted ----
  /// The person using the app on this device: a first name or nickname, or empty (it is optional).
  String user = '';

  /// Optional school or class, shown with the name.
  String school = '';
  String board = 'v2';

  /// kPortSim (the preview board) or kPortUsb (a real board on USB).
  String port = kPortSim;
  int baud = 115200;

  /// The preview board is switched on (Connect / Disconnect while on the simulator).
  bool connected = true;
  String cpu = '240 MHz';
  String partition = '8 MB · 3 MB app / 1.5 MB SPIFFS';
  Settings settings = Settings();
  Map<String, bool> libs = {'esp32servo': true, 'neopixel': true, 'newping': false, 'lcd': false};
  List<Project> projects = [];

  // ---- session ----
  Screen view = Screen.home;
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
  // Stop cancels a Verify or Upload (E-07): each one checks this is still its number after every wait.
  int _buildGen = 0;
  bool _flashing = false;
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
  /// The toast's title, its optional message, and its kind (the design's three: success, info, error).
  String? toast, toastBody;

  /// The toast is an error: it stays until it is closed (G-16).
  bool toastError = false;
  bool toastInfo = false;
  Timer? _toastTimer;

  /// Set in the macOS app: shows a toast as a system notification instead, and answers false when the
  /// system won't (the user turned them off), so the toast shows in the window after all.
  Future<bool> Function(String title, String? body, bool error)? systemToast;

  /// The macOS app's projects folder, once the user chose one: the projects are files there (project_folder.dart),
  /// and only the settings are saved here. Null: the projects are saved with the settings, as in the web app.
  ProjectFolder? folder;

  /// Set in the macOS app: asks the user for a projects folder (null when they cancel).
  Future<ProjectFolder?> Function()? chooseFolder;

  /// Set in the macOS app: the projects folder at a saved path, if it is there.
  ProjectFolder? Function(String path)? folderAt;

  /// The projects folder, when it was chosen before but can't be opened now (moved, renamed, or on a drive that
  /// isn't there). The projects then live here until it is chosen again.
  String? missingFolder;
  String? _savedFolder;
  bool _folderAsked = false;

  /// The Mac app asks once whether to keep the projects as files (see the Shell).
  bool get shouldAskFolder => chooseFolder != null && folder == null && missingFolder == null && !_folderAsked;

  void folderAsked() {
    _folderAsked = true;
    try {
      _prefs?.setBool('rc-folder-asked', true);
    } catch (_) {}
  }
  int logVersion = 0;

  // ---- USB board ----
  bool usbOpen = false;
  String? usbLabel;
  int? uploadPct;
  int _lastPctLine = -10;
  String _rxBuf = '';
  Timer? _rxTimer;

  /// Set when stored projects could not be read; shown once after loading.
  String? loadNotice;

  /// True while [load] reads the saved state at start-up: the window shows "Opening your projects…" (the projects
  /// folder can take a moment, or wait for macOS to ask whether RoboCore may open Documents).
  bool loading = false;

  /// Bumped on every serial line, so only log views rebuild.
  final ValueNotifier<int> logTick = ValueNotifier(0);

  Project? get cur {
    for (final p in projects) {
      if (p.id == pid) return p;
    }
    return null;
  }

  List<Project> get sortedProjects => [...projects]..sort((a, b) => b.updated.compareTo(a.updated));

  /// Projects page: newest first, through the chips (All / Blocks / C++) and the filter field.
  List<Project> get filteredProjects {
    final q = pfilter.trim().toLowerCase();
    return sortedProjects
        .where((p) =>
            (ptab == 'all' || p.mode == ptab) &&
            (q.isEmpty || p.name.toLowerCase().contains(q) || kBoards[p.board]!.name.toLowerCase().contains(q)))
        .toList();
  }
  String get boardId => (view == Screen.editor && cur != null) ? cur!.board : board;
  Set<String> get installedLibs => {for (final e in libs.entries) if (e.value) e.key};

  /// Whether the welcome screen was answered on this device. The name is optional, so this is kept apart from it.
  bool welcomed = false;

  /// True until the welcome screen was answered (first start).
  bool get needsProfile => !welcomed;

  /// First name, for greetings.
  String get firstName => user.trim().split(RegExp(r'\s+')).first;

  /// Up to two initials for the avatar ("Thandi Mokoena" → "TM"); empty without a name.
  String get initials {
    final words = user.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    String first(String w) => String.fromCharCode(w.runes.first);
    final a = first(words.first);
    final b = words.length > 1 ? first(words.last) : '';
    return (a + b).toUpperCase();
  }

  /// A name is optional: a first name or a nickname is enough, and nothing at all is fine too.
  String? validateProfileName(String name) {
    if (name.trim().length > 40) return 'Use 40 characters or fewer.';
    return null;
  }

  /// Saves the name (and optional school or class) for this device.
  void setProfile({required String name, String school = ''}) {
    welcomed = true;
    user = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    this.school = school.trim();
    // After Reset all data the next profile starts with the starter projects again (W-04).
    if (projects.isEmpty) _seed();
    persist(now: true);
    notifyListeners();
  }

  bool get onUsb => port == kPortUsb;
  bool get hasServer => settings.compileServer.trim().isNotEmpty;

  /// Something is there to talk to: the open USB port, or the preview board when it is switched on.
  bool get linked => onUsb ? usbOpen : connected;

  /// The socket of the board in use, as messages name it: USB-C on the RoboCore V2, USB on the others.
  String get usbName => kBoards[boardId]!.usb;

  /// Which of our boards is on USB, from its USB ids (in [usbLabel], e.g. "Arduino Uno (2341:0043)"): 'uno' (an
  /// Arduino Uno), 'v2' (Espressif's own USB, the RoboCore V2's ESP32-S3) or 'esp32' (a CP210x bridge: an ESP32
  /// DevKit or NodeMCU). Null when nothing is connected or the ids don't say (a CH340 clone can be either).
  String? get usbBoardKind {
    if (!usbOpen) return null;
    final m = RegExp(r'\(([0-9A-F]{4}):([0-9A-F]{4})\)').firstMatch(usbLabel ?? '');
    if (m == null) return null;
    final vid = int.parse(m[1]!, radix: 16), pid = int.parse(m[2]!, radix: 16);
    if ((vid == 0x2341 || vid == 0x2a03) && const [0x0001, 0x0043, 0x0243].contains(pid)) return 'uno';
    if (vid == 0x303a) return 'v2';
    if (vid == 0x10c4) return 'esp32';
    return null;
  }

  /// The board new projects and examples start on: the one plugged in when the app can tell, else the default.
  String get newProjectBoard {
    final k = usbBoardKind;
    return k == 'uno' || k == 'v2' ? k! : board;
  }

  /// Why [p] can't be uploaded to the board on USB: it is set to another kind of board (the sketch would be built
  /// for the wrong chip). Null when they match, or when the app can't tell.
  String? usbBoardMismatch(Project p) {
    final k = usbBoardKind;
    if (k == null) return null;
    final b = kBoards[p.board]!;
    final same = k == 'esp32' ? b.arch == 'esp32' && b.id != 'v2' : k == b.id;
    if (same) return null;
    final onUsb = k == 'esp32' ? 'an ESP32 board' : kBoards[k]!.name;
    final pick = k == 'esp32' ? '${kBoards['devkit']!.name} or ${kBoards['nodemcu']!.name}' : kBoards[k]!.name;
    return 'The board on USB is $onUsb, but “${p.name}” is set to ${b.name}. Pick $pick in the board menu, then press Upload again.';
  }

  String get portLabel => onUsb
      ? (usbOpen ? '$usbName · ${usbLabel ?? 'board'}' : '$usbName (not connected)')
      : 'Preview board (simulator)';

  String get portShort => onUsb ? (usbOpen ? usbName : 'no port') : (connected ? 'preview' : 'off');

  List<(String, String)> get portItems => [
        (kPortSim, 'Preview board (simulator)'),
        (kPortUsb, usbOpen ? '$usbName · ${usbLabel ?? 'board'}' : (usb.supported ? '$usbName board…' : '$usbName board (Chrome or Edge only)')),
      ];

  // ---------- persistence ----------
  Future<void> load() async {
    String? raw;
    try {
      _prefs = await SharedPreferences.getInstance();
      raw = _prefs!.getString(_storeKey);
      _folderAsked = _prefs!.getBool('rc-folder-asked') ?? false;
    } catch (_) {
      raw = null;
    }
    if (raw != null) _restoreSaved(raw);
    await _openFolder(raw);
    if (projects.isEmpty && missingFolder == null) _seed();
    if (onUsb) {
      serialPush('Looking for the board on $usbName…', 'sys');
      unawaited(_autoReconnect());
    } else {
      final real = boardId == 'v2' ? 'a RoboCore' : 'the ${kBoards[boardId]!.name}';
      serialPush('Preview board ready at $baud baud. Plug in $real and pick $usbName in Board Setup to use the real one.', 'sys');
      _bootBoard();
    }
    if (loadNotice != null) showToast(loadNotice!, error: true);
    loading = false;
    notifyListeners();
  }

  /// Reads the saved state one piece at a time, so one damaged project (or setting) never
  /// throws away the rest. Anything that can't be read is kept under a backup key, not deleted.
  void _restoreSaved(String raw) {
    Map<String, dynamic> o;
    try {
      o = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      _keepAside('$_storeKey-unreadable', raw);
      loadNotice = 'Your saved projects could not be read. A copy was kept on this device; the samples were restored.';
      return;
    }
    if (o['v'] != 1) return;
    T? field<T>(T? Function() f) {
      try {
        return f();
      } catch (_) {
        return null;
      }
    }

    // Saves from before the welcome screen always held the sample name, so only trust a
    // name the user typed in (marked with 'profile': true); otherwise ask once.
    if (field(() => o['profile'] as bool?) == true) {
      welcomed = true;
      user = field(() => o['user'] as String?) ?? '';
      school = field(() => o['school'] as String?) ?? '';
    }
    board = field(() => o['board'] as String?) ?? board;
    if (!kBoards.containsKey(board)) board = 'v2';
    port = field(() => o['port'] as String?) == kPortUsb ? kPortUsb : kPortSim;
    baud = field(() => (o['baud'] as num?)?.toInt()) ?? baud;
    connected = field(() => o['connected'] as bool?) ?? connected;
    cpu = field(() => o['cpu'] as String?) ?? cpu;
    partition = field(() => o['partition'] as String?) ?? partition;
    settings = field(() => Settings.fromJson(((o['settings'] as Map?) ?? const {}).cast<String, dynamic>())) ?? settings;
    libs = field(() => {...libs, ...((o['libs'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v == true))}) ?? libs;
    _savedFolder = field(() => o['folder'] as String?);
    sideCollapsed = field(() => _prefs?.getBool('rc-side')) ?? false;
    panelOpen = field(() => _prefs?.getBool('rc-panel')) ?? true;

    final list = o['projects'];
    final bad = <dynamic>[];
    if (list is List) {
      for (final item in list) {
        try {
          final pr = Project.fromJson((item as Map).cast<String, dynamic>());
          if (!kBoards.containsKey(pr.board)) pr.board = 'v2';
          if (pr.files.isEmpty) throw const FormatException('no files');
          projects.add(pr);
        } catch (_) {
          bad.add(item);
        }
      }
    }
    if (bad.isNotEmpty) {
      _keepAside('$_storeKey-damaged', jsonEncode(bad));
      final n = bad.length;
      loadNotice = '$n saved project${n == 1 ? '' : 's'} could not be opened and ${n == 1 ? 'was' : 'were'} set aside. '
          'Your other projects are fine.';
    }
  }

  /// The projects come from the projects folder when there is one. Projects saved here (before the folder was chosen,
  /// or while it was missing) move into it; a copy of what was saved is kept aside first.
  Future<void> _openFolder(String? raw) async {
    if (folder == null && _savedFolder != null) folder = folderAt?.call(_savedFolder!);
    final f = folder;
    if (f == null) {
      if (_savedFolder != null) {
        missingFolder = _savedFolder;
        loadNotice ??= 'Your projects folder ($missingFolder) can’t be opened. If you moved or renamed it, choose it '
            'again in Settings → Projects folder. Until then, new projects are kept in the app.';
      }
      return;
    }
    final here = projects;
    try {
      projects = await f.readAll(defaultBoard: board);
    } catch (_) {
      projects = here;
      folder = null;
      missingFolder = f.path;
      loadNotice ??= 'Your projects folder ($missingFolder) could not be read. Choose it again in Settings → Projects folder.';
      return;
    }
    if (here.isNotEmpty) {
      if (raw != null) _keepAside('$_storeKey-before-folder', raw);
      _addProjects(here);
      persist(now: true);
    }
  }

  /// Adds [more] (from the app, or a folder) to the projects, except ones already there: each keeps a name and a
  /// main file no other project has.
  void _addProjects(List<Project> more) {
    for (final p in more) {
      if (projects.any((x) => x.id == p.id)) continue;
      if (projects.any((x) => x.name.toLowerCase() == p.name.toLowerCase())) p.name = _freeName(p.name);
      _uniqueMain(p);
      projects.add(p);
    }
  }

  /// Gives [p] a main file whose name no other project's has (case aside): in a projects folder each project is a
  /// sketch folder named after it (copies of one example all start as Blink.ino, say).
  void _uniqueMain(Project p) {
    String base(Project x) => sketchFolderName(x.files.first.name).toLowerCase();
    bool taken(String b) => projects.any((x) => !identical(x, p) && base(x) == b.toLowerCase());
    if (!taken(base(p))) return;
    final b = fileBase(p.name);
    var name = b;
    for (var n = 2; taken(name); n++) {
      name = '$b$n';
    }
    p.files.first.name = '$name.ino';
  }

  /// Settings → Projects folder: from now on the projects are files in the folder the user picks. The app's
  /// projects go there too, and sketches already in that folder join them. False when the user cancels.
  Future<bool> chooseProjectsFolder() async {
    final f = await chooseFolder?.call();
    if (f == null) return false;
    final mine = projects;
    try {
      projects = await f.readAll(defaultBoard: board);
    } catch (_) {
      projects = mine;
      showToast('That folder can’t be used', body: 'RoboCore could not read it. Choose another one.', error: true);
      return false;
    }
    folder = f;
    missingFolder = null;
    _addProjects(mine);
    persist(now: true);
    showToast('Projects are now files', body: 'They are in ${f.path}, one folder each.');
    notifyListeners();
    return true;
  }

  /// File → Open Sketch… (macOS): a copy of an Arduino sketch as a new code project.
  void importSketch(String name, Map<String, String> files) {
    final main = files.keys.where((n) => n.toLowerCase().endsWith('.ino')).toList()
      ..sort((a, b) => (b.toLowerCase() == '${name.toLowerCase()}.ino' ? 1 : 0) - (a.toLowerCase() == '${name.toLowerCase()}.ino' ? 1 : 0));
    if (main.isEmpty) return showToast('There is no .ino file there', error: true);
    final nm = name.replaceAll(RegExp(r'[^A-Za-z0-9 ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final p = Project(
      id: uid(),
      name: _freeName(nm.isEmpty ? 'Sketch' : nm),
      board: board,
      mode: 'code',
      setup: [],
      loop: [],
      files: [
        ProjectFile(main.first, files[main.first]!),
        for (final n in files.keys.where((n) => n != main.first).toList()..sort()) ProjectFile(n, files[n]!),
      ],
      codeEdited: true,
      autosave: settings.autosave,
      updated: DateTime.now().millisecondsSinceEpoch,
    );
    _uniqueMain(p);
    projects.add(p);
    persist(now: true);
    openProject(p.id);
    showToast('Opened ${main.first}', body: folder != null ? 'A copy is in your projects folder.' : 'A copy is in Projects.');
  }

  void _keepAside(String key, String value) {
    try {
      _prefs?.setString('$key-${DateTime.now().millisecondsSinceEpoch}', value);
    } catch (_) {}
  }

  /// Starter projects for a new user: a short "getting started" set, newest first.
  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final starters = ['blink', 'distance', 'button', 'line', 'obstacle'];
    projects = [
      for (var i = 0; i < starters.length; i++) projectFrom(exampleById(starters[i]), board: board, updated: now - i * 1000),
    ];
    persist(now: true);
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'profile': welcomed,
        'user': user,
        'school': school,
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
      final j = toJson();
      final f = folder;
      if (f != null) {
        j['projects'] = []; // they are files in the folder
        j['folder'] = f.path;
        f.write(projects);
      } else if (missingFolder != null) {
        j['folder'] = missingFolder;
      }
      try {
        _prefs?.setString(_storeKey, jsonEncode(j));
      } catch (_) {}
    }

    if (now) {
      w();
    } else {
      _persistTimer = Timer(const Duration(milliseconds: 400), w);
    }
  }

  /// A toast: a short [title] and, under it, a [body]. Success (the default) and [info] hide after 4 s; an [error]
  /// stays until closed (G-16).
  void showToast(String title, {String? body, bool error = false, bool info = false}) {
    final system = systemToast;
    if (system != null) {
      system(title, body, error).then((shown) {
        if (!shown) _showToast(title, body, error, info);
      });
      return;
    }
    _showToast(title, body, error, info);
  }

  void _showToast(String title, String? body, bool error, bool info) {
    toast = title;
    toastBody = body;
    toastError = error;
    toastInfo = info && !error;
    _toastTimer?.cancel();
    if (!error) {
      _toastTimer = Timer(const Duration(seconds: 4), () {
        toast = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void closeToast() {
    _toastTimer?.cancel();
    toast = null;
    notifyListeners();
  }

  void setStatus(String label, [String kind = '']) {
    stateLabel = label;
    stateKind = kind;
  }

  // ---------- navigation ----------
  void go(Screen v) {
    view = v;
    if (v != Screen.board) conn = null;
    if (v == Screen.board) bsel = null;
    if (v == Screen.editor && cur == null) {
      final s = sortedProjects;
      if (s.isEmpty) {
        view = Screen.home;
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
    go(Screen.editor);
  }

  void openExample(String id) {
    final ex = exampleById(id);
    final name = _freeName(ex.proj);
    final p = projectFrom(ex, name: name, board: newProjectBoard);
    p.autosave = settings.autosave;
    _uniqueMain(p);
    projects.add(p);
    persist(now: true);
    showToast('Copied to your projects', body: '“${ex.name}” is in Projects as $name.');
    openProject(p.id);
  }

  /// Project names are required, plain and unique ([except]: the project being renamed).
  String? validateName(String name, {Project? except}) {
    final t = name.trim();
    if (t.isEmpty) return 'Give your project a name.';
    if (!RegExp(r'^[A-Za-z0-9 ]+$').hasMatch(t)) return 'Use only letters, numbers and spaces.';
    if (t.length > 40) return 'Use 40 characters or fewer.';
    if (projects.any((p) => !identical(p, except) && p.name.toLowerCase() == t.toLowerCase())) {
      return 'You already have a project called “$t”.';
    }
    return null;
  }

  /// [base], or [base] 2, 3 … if a project already has that name.
  String _freeName(String base) {
    var name = base;
    var n = 2;
    while (projects.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      name = '$base ${n++}';
    }
    return name;
  }

  void renameProject(Project p, String name) {
    p.name = name.trim();
    saveNow(p);
    showToast('Renamed to “${p.name}”');
  }

  /// A copy named “… copy”, at the top of Projects (PR-06).
  void duplicateProject(Project p) {
    p.syncCode();
    final d = p.copy()
      ..id = uid()
      ..name = _freeName('${p.name} copy')
      ..updated = DateTime.now().millisecondsSinceEpoch;
    _uniqueMain(d);
    projects.add(d);
    persist(now: true);
    showToast('Project duplicated', body: '“${d.name}” is in Projects.');
    notifyListeners();
  }

  /// The sketch for Arduino IDE 2 (PR-07): the main .ino, or a .zip with a folder named after it when
  /// the sketch has more than one tab. Native apps copy the main file to the clipboard instead.
  Future<void> downloadProject(Project p) async {
    p.syncCode();
    final f = this.folder; // (the zip's folder name below is also called folder)
    if (f != null) {
      // The sketch is already a folder of files: show it.
      persist(now: true);
      await f.reveal(p);
      return;
    }
    final main = p.files.first.name;
    final folder = main.replaceAll(RegExp(r'\.ino$'), '');
    final one = p.files.length == 1;
    final ok = one
        ? downloadFile(main, utf8.encode(p.files.first.content), 'text/plain;charset=utf-8')
        : downloadFile('$folder.zip', zipFiles({for (final f in p.files) '$folder/${f.name}': f.content}), 'application/zip');
    if (ok) {
      showToast(one ? 'Downloaded $main' : 'Downloaded $folder.zip',
          body: one ? 'Open it in Arduino IDE 2 to work offline.' : 'Unzip it and open $main in Arduino IDE 2.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: p.files.first.content));
    showToast('Copied $main to the clipboard', body: 'Downloads work in the web app.', info: true);
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
    _uniqueMain(p);
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
    showToast('Project settings saved');
  }

  void deleteProject(Project p) {
    final name = p.name;
    final open = p.id == pid;
    projects.remove(p);
    unawaited(folder?.remove(p)); // its folder goes to the Trash
    persist(now: true);
    showToast('Deleted $name');
    if (open) {
      sim.stop();
      pid = null;
      go(Screen.projects);
    } else {
      notifyListeners();
    }
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
    if (view == Screen.editor && p != null) {
      p.board = id;
      verified = null;
      problems = [];
      touch(p, immediate: true);
    } else {
      board = id;
      persist(now: true);
    }
    showToast('Board set to ${kBoards[id]!.name}', info: true);
  }

  void setDefaultBoard(String id) {
    board = id;
    bsel = null;
    persist(now: true);
    showToast('${kBoards[id]!.name} is now your default board');
  }

  void selectBoardDetail(String id) {
    bsel = id;
    conn = null;
    notifyListeners();
  }

  Future<void> testConnection() async {
    if (onUsb) {
      if (!usbOpen || busy != null) {
        conn = ConnMsg(
            'err',
            !usb.supported
                ? UsbResult.unsupported.message
                : busy != null
                    ? 'Wait for the ${busy == 'upload' ? 'upload' : 'build'} to finish, then test again.'
                    : 'No board on $usbName. Plug it in and press Connect.');
        notifyListeners();
        return;
      }
      // Ask the chip its name through its bootloader (B-04). The board restarts, so its sketch starts again.
      busy = 'test';
      conn = const ConnMsg('', 'Asking the board its name… (it restarts)');
      _flushRx();
      notifyListeners();
      final r = await usb.identify(baud: baud, arch: kBoards[board]!.arch);
      busy = null;
      usbOpen = usb.isOpen;
      if (r.ok) {
        final chip = '${r.data['chip'] ?? 'the chip'}';
        final b = kBoards[board]!;
        final same = chip.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '').startsWith(b.chip.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), ''));
        if (same) {
          conn = ConnMsg('ok', 'Board answered: $chip on ${r.data['label'] ?? usbLabel ?? 'USB'}. It restarted and is running its sketch again.');
          showToast('Board answered', body: '$chip on ${r.data['label'] ?? usbLabel ?? 'USB'}.');
        } else {
          conn = ConnMsg('err', 'The board answered, but it has an $chip and Board Setup is set to ${b.name} (${b.chip}). Pick the right board.');
          showToast('Board answered', body: 'It has an $chip, not ${b.chip}. Pick the right board.', error: true);
        }
        serialPush('— board restarted —', 'sys');
      } else if (r.code == 'avr-sync') {
        conn = ConnMsg('err', '${r.message} ${kAvrTip.replaceFirst('press Upload', 'press Test connection')}');
        showToast('The board did not answer', body: 'Check the board in Board Setup, and close other apps using the port.', error: true);
      } else {
        conn = ConnMsg(
            'err',
            r.code == 'bootloader'
                ? 'The board did not answer. Hold BOOT, tap RESET, release BOOT, then press Test connection again.'
                : r.message);
        // BOOT and RESET are ESP32 buttons; an Uno has neither, so it gets the board-and-port advice instead.
        showToast('The board did not answer',
            body: kBoards[board]!.arch == 'avr'
                ? 'Check the board in Board Setup, and close other apps using the port.'
                : 'Hold BOOT, tap RESET, release BOOT, then test again.',
            error: true);
      }
      notifyListeners();
      return;
    }
    conn = const ConnMsg('', 'Testing…');
    notifyListeners();
    Timer(const Duration(milliseconds: 700), () {
      conn = connected
          ? ConnMsg('ok', 'The preview ${kBoards[board]!.name} answered in ${8 + _rnd.nextInt(10)} ms.')
          : const ConnMsg('err', 'The preview board is switched off. Press Connect first.');
      notifyListeners();
    });
  }

  /// Disconnect button: closes the USB port, or switches the preview board off.
  void disconnect() {
    if (onUsb) {
      unawaited(disconnectUsb());
      return;
    }
    connected = false;
    sim.stop();
    persist(now: true);
    serialPush('Preview board switched off.', 'sys');
    conn = null;
    notifyListeners();
  }

  /// Connect button: opens the browser's port chooser for USB, or switches the preview board on.
  void connect() {
    if (onUsb) {
      unawaited(connectUsb());
      return;
    }
    connected = true;
    persist(now: true);
    serialPush('Preview board ready at $baud baud.', 'sys');
    conn = const ConnMsg('ok', 'Preview board switched on.');
    notifyListeners();
  }

  void setPort(String v, {bool fromMenu = false}) {
    conn = null;
    if (v == kPortUsb && !usb.supported) {
      // Stay on the preview board and say why (no Web Serial here).
      unawaited(connectUsb());
      notifyListeners();
      return;
    }
    if (v == kPortUsb) {
      final changed = port != kPortUsb;
      port = kPortUsb;
      persist(now: true);
      if (sim.running) sim.stop();
      if (!usbOpen) {
        unawaited(connectUsb());
      } else if (changed) {
        serialPush('Using the board on $usbName.', 'sys');
      }
    } else {
      if (port == kPortSim) return;
      port = kPortSim;
      persist(now: true);
      if (usbOpen) unawaited(disconnectUsb(quiet: true));
      serialPush('Using the preview board (simulator).', 'sys');
      setStatus('Ready');
    }
    notifyListeners();
  }

  void setBaud(int v) {
    baud = v;
    persist(now: true);
    serialPush('Baud rate set to $baud.', 'sys');
    if (onUsb && usbOpen) {
      usb.setBaud(v).then((r) {
        if (!r.ok) serialPush('Could not change the baud rate: ${r.message}', 'err');
      });
    } else if (baud != 115200 && sim.running) {
      serialPush('The sketch prints at 115200 baud, so text may look garbled at this rate.', 'err');
    }
    notifyListeners();
  }

  // ---------- USB board ----------
  /// Opens the browser's port chooser. Call it straight from a click (browsers require that).
  Future<void> connectUsb() async {
    if (!usb.supported) {
      conn = ConnMsg('err', UsbResult.unsupported.message);
      serialPush(UsbResult.unsupported.message, 'err');
      showToast(UsbResult.unsupported.message, error: true);
      return;
    }
    conn = ConnMsg('', 'Pick the board in the browser’s list: ${kBoards[boardId]!.pickAs}…');
    notifyListeners();
    final r = await usb.connect(baud: baud);
    if (!r.ok) {
      conn = r.code == 'cancelled' ? const ConnMsg('', 'No port chosen.') : ConnMsg('err', r.message);
      if (r.code != 'cancelled') serialPush(r.message, 'err');
      notifyListeners();
      return;
    }
    _usbUp(r.data['label'] as String?, 'Connected to');
  }

  Future<void> disconnectUsb({bool quiet = false}) async {
    await usb.disconnect();
    _flushRx();
    usbOpen = false;
    if (!quiet) serialPush('Disconnected from ${usbLabel ?? 'the USB board'}.', 'sys');
    conn = null;
    notifyListeners();
  }

  /// Restarts the sketch on the real board (RESET through the USB serial lines).
  Future<void> resetUsbBoard() async {
    if (!usbOpen) return;
    final r = await usb.reset(arch: kBoards[boardId]!.arch);
    if (!r.ok) serialPush('Could not reset the board: ${r.message}', 'err');
  }

  Future<void> _autoReconnect() async {
    if (!usb.supported) {
      serialPush('${UsbResult.unsupported.message} Using the preview board until then.', 'sys');
      return;
    }
    final r = await usb.reconnect(baud: baud);
    if (r.ok) {
      _usbUp(r.data['label'] as String?, 'Reconnected to');
    } else {
      serialPush('No board on $usbName yet. Plug in the ${kBoards[boardId]!.name} and press Connect in Board Setup.', 'sys');
      notifyListeners();
    }
  }

  void _usbUp(String? label, String verb) {
    usbOpen = true;
    usbLabel = label ?? 'USB board';
    port = kPortUsb;
    if (sim.running) sim.stop();
    persist(now: true);
    serialPush('$verb $usbLabel at $baud baud.', 'sys');
    conn = ConnMsg('ok', '$verb $usbLabel.');
    setStatus('Ready');
    notifyListeners();
  }

  void _onUsbText(String t) {
    _rxBuf += t;
    var k = _rxBuf.indexOf('\n');
    while (k >= 0) {
      var line = _rxBuf.substring(0, k);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      serialPush(line, 'out');
      _rxBuf = _rxBuf.substring(k + 1);
      k = _rxBuf.indexOf('\n');
    }
    _rxTimer?.cancel();
    if (_rxBuf.length > 2000) {
      _flushRx();
    } else if (_rxBuf.isNotEmpty) {
      // Text without a newline yet (a prompt): show it if nothing more comes soon.
      _rxTimer = Timer(const Duration(milliseconds: 300), _flushRx);
    }
  }

  void _flushRx() {
    _rxTimer?.cancel();
    if (_rxBuf.isEmpty) return;
    var line = _rxBuf;
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    _rxBuf = '';
    serialPush(line, 'out');
  }

  void _onUsbEvent(String type, String msg) {
    switch (type) {
      case 'unplugged':
        _flushRx();
        usbOpen = false;
        serialPush('Board unplugged ($msg). Plug it back in and it reconnects by itself.', 'err');
        setStatus('Not connected', 'err');
        showToast('Board unplugged', body: 'Plug it back in to reconnect.', error: true);
        break;
      case 'reconnected':
        usbOpen = true;
        usbLabel = msg;
        serialPush('Board reconnected ($msg).', 'sys');
        setStatus('Ready');
        showToast('Board reconnected');
        break;
      case 'restarted':
        usbOpen = true;
        serialPush('— board restarted —', 'sys');
        break;
      case 'plugged':
        if (!usbOpen) showToast('A board was plugged in', body: '$msg. Press Connect in Board Setup to use it.', info: true);
        break;
      case 'error':
        serialPush(msg, 'err');
        break;
      case 'log':
        // esptool-js output; the progress lines come from 'progress' below.
        final line = msg.trimRight();
        if (busy == 'upload' && line.isNotEmpty && !line.startsWith('Writing at')) outLine(line, 'sys');
        break;
      case 'stage':
        if (busy != 'upload') break;
        switch (msg) {
          case 'connecting':
            outLine('Resetting the board into its bootloader…');
          case 'writing':
            outLine('Writing the program…');
          case 'verifying':
            outLine('Checking what was written…');
          case 'resetting':
            outLine('Restarting the board…');
          case 'reopening':
            outLine('Reopening the Serial Monitor…');
        }
        break;
      case 'progress':
        _onProgress(msg);
        break;
    }
    notifyListeners();
  }

  void _onProgress(String json) {
    try {
      final m = (jsonDecode(json) as Map).cast<String, dynamic>();
      final done = (m['done'] as num).toDouble(), total = (m['total'] as num).toDouble();
      final pct = total <= 0 ? 0 : (done * 100 / total).floor().clamp(0, 100).toInt();
      uploadPct = pct;
      setStatus('Uploading $pct %', 'busy');
      if (pct >= _lastPctLine + 10 || pct == 100 && _lastPctLine < 100) {
        _lastPctLine = pct - pct % 10;
        final addr = ((m['address'] as num?)?.toInt() ?? 0).toRadixString(16).padLeft(8, '0');
        outLine('Writing ${m['name'] ?? ''} at 0x$addr… ($pct %)');
      }
    } catch (_) {}
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
      showToast('${l.name} installed', body: 'Version ${l.ver}. You can #include it now.');
    });
  }

  void uninstall(String id) {
    libs[id] = false;
    persist(now: true);
    showToast('${kLibs.firstWhere((x) => x.id == id).name} removed', info: true);
  }

  // ---------- settings ----------
  void updateSettings(void Function(Settings s) f) {
    f(settings);
    persist(now: true);
    notifyListeners();
  }

  void setCompileServer(String url) {
    settings.compileServer = normalizeServerUrl(url);
    persist(now: true);
    notifyListeners();
  }

  /// Settings → Compile server → Test.
  Future<(bool, String)> checkServer([String? url]) => compiler.health(url ?? settings.compileServer);

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
    final end = const {'nl': '\n', 'none': '', 'cr': '\r', 'both': '\r\n'}[lineEnd] ?? '\n';
    if (onUsb) {
      if (!usbOpen) {
        serialPush('The board is not connected. Press Connect in Board Setup.', 'err');
        return;
      }
      serialPush(text, 'in');
      usb.write(text + end).then((r) {
        if (!r.ok) serialPush('Could not send: ${r.message}', 'err');
      });
      return;
    }
    if (!connected) {
      serialPush('Preview board switched off. Connect it in Board Setup.', 'err');
      return;
    }
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

  /// The trash on the Problems tab: the list and the editor's squiggles go until the next Verify.
  void clearProblems() {
    problems = [];
    notifyListeners();
  }

  // ---------- build ----------
  /// Verify: a real C++ compile on the compile server when one is set, otherwise the built-in
  /// preview check. Returns the preview result (used to run the sketch on the preview board).
  Future<CompileResult?> verify({bool fromUpload = false}) async {
    final p = cur;
    if (p == null || busy != null) return null;
    if (!fromUpload && (hasServer || _buildsHere(p))) {
      await _buildOnServer(p, flash: false);
      return null;
    }
    p.syncCode();
    busy = 'verify';
    final gen = ++_buildGen;
    problems = [];
    verified = null;
    if (!fromUpload) output.clear();
    final b = kBoards[p.board]!;
    final sw = Stopwatch()..start();
    outLine('Checking the sketch for ${b.full} (preview check)…', 'info');
    setStatus('Verifying…', 'busy');
    panelOpen = true;
    if (panelTab == 'problems' || !fromUpload) panelTab = 'output';
    notifyListeners();
    await Future<void>.delayed(Duration(milliseconds: 650 + _rnd.nextInt(450)));
    if (gen != _buildGen) return null;
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
      outLine('Compilation failed with ${r.errors.length} error${r.errors.length > 1 ? 's' : ''}.', 'hint');
      if (!hasServer) {
        outLine('This was the built-in preview check. For a full C++ compile, add a compile server in Settings.', 'sys');
      }
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
    if (onUsb) {
      // Caught before building: a sketch for another chip can't go on this board.
      final wrong = usbBoardMismatch(p);
      if (wrong != null) {
        output.clear();
        outLine(wrong, 'err');
        panelTab = 'output';
        panelOpen = true;
        showToast('This project is for another board', body: wrong, error: true);
        notifyListeners();
        return;
      }
      if (!p.autosave) saveNow(p);
      await _buildOnServer(p, flash: true);
      return;
    }
    if (!connected) {
      output.clear();
      outLine('The preview board is switched off. Connect it in Board Setup, or pick $usbName for a real board.', 'err');
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
    final gen = _buildGen;
    setStatus('Uploading…', 'busy');
    outLine('Connecting to the preview ${b.name}…');
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (gen != _buildGen) return;
    outLine('Chip is ${b.chip}. Writing ${fmtN(r.size)} bytes…');
    for (final pc in const [18, 46, 73, 100]) {
      final addr = (0x10000 + (r.size * pc / 100).round()).toRadixString(16).padLeft(8, '0');
      outLine('Writing at 0x$addr… ($pc %)');
      notifyListeners();
      await Future<void>.delayed(Duration(milliseconds: 170 + _rnd.nextInt(120)));
      if (gen != _buildGen) return;
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

  /// Compiles on the compile server, shows the problems, and (for Upload) flashes the board on USB.
  Future<void> _buildOnServer(Project p, {required bool flash}) async {
    p.syncCode();
    final b = kBoards[p.board]!;
    output.clear();
    problems = [];
    verified = null;
    panelOpen = true;
    panelTab = 'output';
    final here = _buildsHere(p);
    if (!here && !hasServer) {
      outLine('Uploading to a real board needs the compile server. Add its address in Settings → Compile server '
          '(server/README.md shows how to run one).', 'err');
      setStatus('No compile server', 'err');
      showToast('No compile server', body: 'Add one in Settings to upload to the real board.', error: true);
      notifyListeners();
      return;
    }
    // Libraries decides what a sketch may #include (L-04), even though the server has them all.
    final missing = missingLibraries([for (final f in p.files) SourceFile(f.name, f.content)], installedLibs);
    if (missing.isNotEmpty) {
      problems = missing;
      for (final e in missing) {
        outLine('${e.file}:${e.line}: error: ${e.msg}', 'err');
      }
      panelTab = 'problems';
      setStatus('Errors', 'err');
      notifyListeners();
      return;
    }
    busy = flash ? 'upload' : 'verify';
    final gen = ++_buildGen;
    final sw = Stopwatch()..start();
    outLine('Compiling ${p.files.first.name} for ${b.full} ${here ? 'on this Mac' : 'on the compile server'}…', 'info');
    setStatus('Compiling…', 'busy');
    notifyListeners();
    final files = [for (final f in p.files) SourceFile(f.name, f.content)];
    final r = here
        ? await local!.compile(
            board: p.board,
            files: files,
            onLog: (line) {
              if (gen != _buildGen) return;
              outLine(line);
              notifyListeners();
            })
        : await compiler.compile(serverUrl: settings.compileServer, board: p.board, files: files);
    if (gen != _buildGen) return;
    if (r.error != null) {
      busy = null;
      outLine(r.error!, 'err');
      setStatus(r.retry && !here ? 'Server not reachable' : 'Build failed', 'err');
      notifyListeners();
      return;
    }
    final logLines = r.log.split('\n').where((l) => l.trim().isNotEmpty).toList();
    for (final l in logLines.skip(math.max(0, logLines.length - 20))) {
      outLine(l.trimRight());
    }
    problems = r.problems;
    for (final e in r.problems) {
      outLine('${e.file}:${e.line}${e.column > 0 ? ':${e.column}' : ''}: ${e.severity}: ${e.msg}', e.isError ? 'err' : 'sys');
    }
    if (!r.ok) {
      busy = null;
      final n = math.max(1, r.errors.length);
      outLine('Compilation failed with $n error${n == 1 ? '' : 's'}.', 'hint');
      panelTab = 'problems';
      setStatus('Errors', 'err');
      notifyListeners();
      return;
    }
    if (r.flashUsed != null) {
      final max = r.flashMax ?? b.max;
      final pct = math.max(1, (r.flashUsed! / max * 100).round());
      final rp = r.ramUsed == null ? 0 : math.max(1, (r.ramUsed! / (r.ramMax ?? b.ram) * 100).round());
      verified = Verified(r.flashUsed!, pct, rp);
    }
    outLine('Compiled in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s${flash ? '' : ' — ready to upload'}', 'ok');
    if (!flash) {
      busy = null;
      setStatus('Verified');
      notifyListeners();
      return;
    }
    await _flash(p, b, r, gen);
  }

  Future<void> _flash(Project p, BoardDef b, ServerBuild r, int gen) async {
    final img = r.image;
    // An ESP32 build comes as parts at flash offsets (esptool-js); an Uno build as Intel HEX (its Optiboot bootloader).
    final hex = img?['format'] == 'hex' && img?['data'] is String;
    if (!hex && (img == null || img['format'] != 'esp32' || img['parts'] is! List)) {
      busy = null;
      outLine('The compile server sent no program image for this board.', 'err');
      setStatus('Not uploaded', 'err');
      notifyListeners();
      return;
    }
    if (!usbOpen) {
      final rc = await usb.reconnect(baud: baud);
      if (gen != _buildGen) return;
      if (rc.ok) {
        _usbUp(rc.data['label'] as String?, 'Reconnected to');
      } else {
        busy = null;
        outLine('No board on ${b.usb}. Plug in the ${b.name}, press Connect (Board Setup), then Upload again.', 'err');
        setStatus('Not connected', 'err');
        notifyListeners();
        return;
      }
    }
    _flushRx();
    uploadPct = 0;
    _lastPctLine = -10;
    _flashing = true;
    setStatus('Uploading…', 'busy');
    outLine('Uploading to the ${b.name} on ${b.usb}…');
    notifyListeners();
    final res = await usb.flash(hex
        // 128-byte pages: the ATmega328P's (the Uno is the only AVR board).
        ? {'format': 'hex', 'hex': img!['data'], 'chip': b.chip, 'boardName': b.name, 'pageSize': 128, 'max': b.max, 'monitorBaud': baud}
        : {
            'parts': img!['parts'],
            'chip': img['chip'] ?? b.chip,
            'boardName': b.name,
            'baud': 921600,
            'monitorBaud': baud,
          });
    _flashing = false;
    busy = null;
    uploadPct = null;
    usbOpen = usb.isOpen;
    if (res.code == 'cancelled') {
      if (res.data['partial'] == true) {
        outLine('Upload cancelled part-way, so the board’s program is incomplete and it may not run. '
            'Upload again before you use it.', 'err');
      } else {
        outLine('Upload cancelled before anything was written. The board restarted with its old program.', 'sys');
      }
      setStatus('Cancelled');
    } else if (res.ok) {
      final bytes = (res.data['bytes'] as num?)?.toInt() ?? 0;
      outLine('Upload complete: ${fmtN(bytes)} bytes written to the ${res.data['chip'] ?? b.chip}. '
          'The board restarted and is running ${p.name}.', 'ok');
      serialPush('— ${b.name} restarted with ${p.name} —', 'sys');
      if (!usbOpen) outLine('The Serial Monitor did not reopen by itself. Press Connect in Board Setup to see the output.', 'sys');
      lastRunName = p.name;
      setStatus('Uploaded');
    } else {
      outLine('Upload failed: ${res.message}', 'err');
      if (res.code == 'bootloader') {
        outLine(kBootTip, 'hint');
        showToast('Upload failed', body: 'Hold BOOT, tap RESET, release BOOT, then Upload again.', error: true);
      } else if (res.code == 'avr-sync') {
        outLine(kAvrTip, 'hint');
        showToast('Upload failed', body: 'The board did not answer. Check the board in Board Setup, and close other apps using the port.', error: true);
      }
      setStatus('Upload failed', 'err');
    }
    notifyListeners();
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

  /// Stop in the top bar: only while a Verify or Upload runs, or the preview board runs a sketch.
  bool get canStop => busy == 'verify' || busy == 'upload' || sim.running;

  /// Stop in the top bar (E-07): cancels the Verify or Upload, or else stops the preview board.
  void stop() {
    if (busy == 'verify' || busy == 'upload') {
      cancelBuild();
    } else {
      stopSketch();
    }
  }

  void cancelBuild() {
    if (busy != 'verify' && busy != 'upload') return;
    if (_flashing) {
      // The flasher stops at its next step and restarts the board; _flash reports it.
      unawaited(usb.cancelFlash());
      setStatus('Cancelling…', 'busy');
      notifyListeners();
      return;
    }
    final what = busy == 'upload' ? 'Upload' : 'Verify';
    _buildGen++;
    busy = null;
    uploadPct = null;
    outLine('$what cancelled.', 'sys');
    setStatus('Cancelled');
    notifyListeners();
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
    if (!connected || onUsb) return;
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

  /// A new tab name: letters, numbers, _ or -, then .ino .h .hpp .c or .cpp, unique in the sketch (CD-03).
  String? validateFileName(Project p, String name) {
    final t = name.trim();
    if (t.isEmpty) return 'Give the file a name, such as motors.h.';
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}\.(ino|h|hpp|c|cpp)$').hasMatch(t)) {
      return 'Letters, numbers, _ or -, then .ino, .h, .hpp, .c or .cpp';
    }
    if (p.files.any((f) => f.name.toLowerCase() == t.toLowerCase())) return 'This sketch already has a file called $t.';
    return null;
  }

  void addFile(Project p, String name) {
    final t = name.trim();
    final header = t.endsWith('.h') || t.endsWith('.hpp');
    p.files.add(ProjectFile(t, header ? '// $t\n#pragma once\n\n' : '// $t\n\n'));
    p.mode = 'code';
    openFile(p.files.length - 1);
    touch(p, immediate: true);
    showToast('Added $t', body: header ? 'Use it with #include "$t".' : null);
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
    showToast('Code rebuilt from the blocks');
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

  /// The console's chevron or Ctrl/⌘+J (C-05); remembered on this device.
  void togglePanel() {
    panelOpen = !panelOpen;
    _prefs?.setBool('rc-panel', panelOpen);
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
    // The old block editor changed the lists, so they are the blocks again (not the Blockly workspace).
    p.blockly = null;
    p.blocklyCode = null;
    verified = null;
    touch(p);
  }

  /// The Blockly editor changed the blocks: keep its workspace and C++, and update the main file
  /// unless it was edited by hand.
  void setBlockly(String json, String code, {int? count}) {
    final p = cur;
    if (p == null) return;
    if (count != null && count != p.blocklyCount) {
      p.blocklyCount = count;
      if (p.blockly == json && p.blocklyCode == code) return notifyListeners();
    }
    if (p.blockly == json && p.blocklyCode == code) return;
    final first = p.blockly == null;
    p.blockly = json;
    p.blocklyCode = code;
    if (!p.codeEdited && p.files.first.content != code) {
      p.files.first.content = code;
      verified = null;
    }
    if (first) {
      // Just opened in Blockly (converted from the old lists): saved with the next real change.
      notifyListeners();
      return;
    }
    verified = null;
    touch(p);
  }

  void addBlock(String t, {String? stack, int? index}) {
    final p = cur;
    if (p == null) return;
    snap();
    final s = stack ?? target;
    final list = p.stack(s);
    final b = <String, dynamic>{'t': t, ...blockDefaults(t, p.board)};
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
    showToast('All blocks removed', body: 'Press Undo to bring them back.', info: true);
  }

  void undo() {
    final p = cur;
    if (p == null) return;
    if (_past.isEmpty) return showToast('Nothing to undo', info: true);
    _future.add(_snapStr(p));
    _restore(p, _past.removeLast());
    _afterBlocks(p);
  }

  void redo() {
    final p = cur;
    if (p == null) return;
    if (_future.isEmpty) return showToast('Nothing to redo', info: true);
    _past.add(_snapStr(p));
    _restore(p, _future.removeLast());
    _afterBlocks(p);
  }

  /// Settings → Reset all data (ST-12): this device's projects, profile and settings go, and Welcome shows.
  Future<void> resetAll() async {
    sim.stop();
    // The project files stay in the projects folder; the app just stops using it.
    final f = folder;
    folder = null;
    missingFolder = null;
    _savedFolder = null;
    await f?.forget();
    if (usbOpen) await disconnectUsb(quiet: true);
    // Everything the app keeps on this device: the saved state with the copies of damaged saves set aside beside it
    // (_keepAside), the rc- preferences (panels, the USB ports allowed, the folder question) and the Mac's build copies.
    try {
      final keys = _prefs?.getKeys().where((k) => k.startsWith(_storeKey) || k.startsWith('rc-')).toList() ?? const <String>[];
      for (final k in keys) {
        await _prefs?.remove(k);
      }
    } catch (_) {}
    _folderAsked = false;
    await local?.forgetBuilds();
    final fresh = Settings();
    welcomed = false;
    user = '';
    school = '';
    board = 'v2';
    port = kPortSim;
    baud = 115200;
    connected = true;
    cpu = '240 MHz';
    partition = '8 MB · 3 MB app / 1.5 MB SPIFFS';
    settings = fresh;
    libs = {'esp32servo': true, 'neopixel': true, 'newping': false, 'lcd': false};
    projects = [];
    pid = null;
    lastRun = null;
    problems = [];
    verified = null;
    output.clear();
    log.clear();
    sideCollapsed = false;
    panelOpen = true;
    ptab = 'all';
    pfilter = '';
    excat = 'All';
    exq = '';
    cog.newChat(notify: false);
    cog.close();
    view = Screen.home;
    setStatus('Ready');
    notifyListeners();
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
