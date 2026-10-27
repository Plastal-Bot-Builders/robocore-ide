// Checks a sketch the way the Arduino compiler would (includes, names, types)
// and estimates program size, so Verify gives realistic results.
import '../data/catalog.dart';
import 'lexer.dart';
import 'parser.dart';

class Problem {
  final String file;
  final int line;
  final String msg;

  /// error | warning | note. Only errors stop a build.
  final String severity;
  final int column;
  const Problem(this.file, this.line, this.msg, {this.severity = 'error', this.column = 0});
  bool get isError => severity == 'error';
}

class DefineInfo {
  final String v, file;
  final int line;
  const DefineInfo(this.v, this.file, this.line);
}

class CompileResult {
  final List<Problem> errors;
  final Node? prog;
  final Map<String, DefineInfo> defines;
  final int size, ram, tokens;
  final BoardDef board;

  /// Names the included libraries add (the RoboCore V2 RC_PIN_… values).
  final Map<String, num> extraConsts;
  const CompileResult({
    required this.errors,
    required this.board,
    this.prog,
    this.defines = const {},
    this.size = 0,
    this.ram = 0,
    this.tokens = 0,
    this.extraConsts = const {},
  });
}

class SourceFile {
  final String name, content;
  const SourceFile(this.name, this.content);
}

const builtinFns = {
  'pinMode', 'digitalWrite', 'digitalRead', 'analogRead', 'analogWrite', 'delay', 'delayMicroseconds', 'millis', //
  'micros', 'random', 'randomSeed', 'map', 'constrain', 'abs', 'min', 'max', 'sqrt', 'pow', 'sq', 'tone', 'noTone',
  'String', 'yield', 'bitRead', 'bitWrite', 'attachInterrupt', 'detachInterrupt', 'sin', 'cos', 'floor', 'ceil', 'round',
  'pulseIn',
};
const espFns = {'rgbLedWrite', 'neopixelWrite', 'ledcAttach', 'ledcWrite'};
const primTypes = {
  'void', 'int', 'float', 'long', 'double', 'byte', 'bool', 'boolean', 'char', 'short', 'word', 'String', 'size_t', //
  'uint8_t', 'uint16_t', 'uint32_t', 'int8_t', 'int16_t', 'int32_t', 'int64_t', 'uint64_t',
};
const qualifiers = {'const', 'unsigned', 'signed', 'static', 'volatile'};

Map<String, num> baseConsts(BoardDef b) {
  final c = <String, num>{
    'HIGH': 1, 'LOW': 0, 'INPUT': 0, 'OUTPUT': 1, 'INPUT_PULLUP': 2, 'true': 1, 'false': 0, //
    'LED_BUILTIN': b.led, 'HEX': 16, 'DEC': 10, 'BIN': 2, 'OCT': 8, 'PI': 3.141592653589793, 'NULL': 0,
  };
  if (b.arch == 'avr') {
    for (var i = 0; i < 6; i++) {
      c['A$i'] = 14 + i;
    }
  } else {
    c['A0'] = 36;
    c['A3'] = 39;
    c['A6'] = 34;
    c['A7'] = 35;
  }
  if (b.id == 'v2') c['RGB_BUILTIN'] = RoboCoreV2Pins.rgbLed;
  return c;
}

/// Pointer and reference marks are not type names.
bool _typeWord(String w) => w.isNotEmpty && w != '*' && w != '&' && w != '**';

final _defineRe = RegExp(r'^\s*#\s*define\s+(\w+)(?:\s+(.*?))?\s*(?:\/\/.*)?$');
final _includeRe = RegExp(r'^\s*#\s*include\s*([<"])([^>"]+)[>"]');

CompileResult compileSketch({
  required List<SourceFile> files,
  required String boardId,
  required Set<String> installedLibs,
}) {
  final b = kBoards[boardId] ?? kBoards['v2']!;
  final main = files.first;
  final errors = <Problem>[];
  void err(String file, int line, String msg) {
    if (!errors.any((e) => e.line == line && e.msg == msg && e.file == file)) errors.add(Problem(file, line, msg));
  }

  final defines = <String, DefineInfo>{};
  final includes = <({String h, bool local, int line, String file})>[];
  void scanPP(SourceFile f) {
    final lines = f.content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final ln = lines[i];
      final d = _defineRe.firstMatch(ln);
      if (d != null) defines[d.group(1)!] = DefineInfo((d.group(2) ?? '').trim(), f.name, i + 1);
      final inc = _includeRe.firstMatch(ln);
      if (inc != null) includes.add((h: inc.group(2)!.trim(), local: inc.group(1) == '"', line: i + 1, file: f.name));
    }
  }

  scanPP(main);
  for (final i in includes.where((i) => i.local).toList()) {
    final f = files.skip(1).where((x) => x.name == i.h);
    if (f.isNotEmpty) {
      scanPP(f.first);
    } else {
      err(i.file, i.line, '${i.h}: No such file or directory');
    }
  }
  final libsIn = <String>{};
  for (final i in includes.where((i) => !i.local)) {
    if (i.h == 'Arduino.h') continue;
    final h = kHeaderAlias[i.h] ?? i.h;
    final libs = kLibs.where((l) => l.h == h);
    if (libs.isEmpty) {
      err(i.file, i.line, '${i.h}: No such file or directory. Check the spelling, or install the library from Libraries.');
      continue;
    }
    final lib = libs.first;
    if (lib.kind == 'opt' && !installedLibs.contains(lib.id)) {
      err(i.file, i.line, notInstalled(lib.name));
      continue;
    }
    if (lib.arch == 'v2' && b.id != 'v2') {
      err(i.file, i.line, 'The ${lib.name} library is made for the RoboCore V2. Pick RoboCore V2 as the board, or remove this #include.');
      continue;
    }
    if (lib.arch == 'esp32' && b.arch != 'esp32') {
      err(i.file, i.line, '${lib.name} only works on ESP32 boards. Pick an ESP32 board, or remove this #include.');
      continue;
    }
    libsIn.add(lib.id);
  }
  // RoboCore.h includes the motors and sensors headers.
  if (libsIn.contains('robocore')) libsIn.addAll(const ['motors', 'sensors']);

  List<Tok> toks;
  Node prog;
  try {
    toks = lex(main.content);
    prog = Parser(toks).program();
  } on CompileError catch (e) {
    err(main.name, e.line, e.msg);
    return CompileResult(errors: errors, board: b);
  }
  final fns = (prog['fns'] as Map).cast<String, Node>();
  if (!fns.containsKey('setup')) err(main.name, 1, "undefined reference to 'setup()'. Every sketch needs a setup() function.");
  if (!fns.containsKey('loop')) err(main.name, 1, "undefined reference to 'loop()'. Every sketch needs a loop() function.");

  final extra = <String, num>{if (libsIn.any(kRoboCoreLibs.contains)) ...{...RoboCoreV2Pins.byCName, ...kRoboCoreConsts}};
  final consts = {...baseConsts(b), ...extra};
  final declared = <String>{...defines.keys};
  walk(prog, (n) {
    if (n['k'] == 'decl') {
      for (final it in n['items'] as List) {
        declared.add(it['name'] as String);
      }
    }
  });
  for (final f in fns.values) {
    for (final pm in f['params'] as List) {
      declared.add(pm['name'] as String);
    }
  }
  final libTypes = <String, LibDef>{};
  for (final l in kLibs) {
    for (final t in l.types) {
      libTypes[t] = l;
    }
  }
  void checkType(String type, int line) {
    for (final w in type.split(RegExp(r'\s+'))) {
      if (!_typeWord(w) || qualifiers.contains(w) || primTypes.contains(w)) continue;
      final lib = libTypes[w];
      if (lib == null) {
        err(main.name, line, "'$w' does not name a type");
      } else if (!libsIn.contains(lib.id)) {
        err(main.name, line, "'$w' does not name a type. Add #include <${lib.h}> at the top of the sketch.");
      }
    }
  }

  for (final f in fns.values) {
    checkType(f['type'] as String, f['line'] as int);
    for (final pm in f['params'] as List) {
      checkType(pm['type'] as String, f['line'] as int);
    }
  }
  walk(prog, (n) {
    final k = n['k'];
    if (k == 'decl') checkType(n['type'] as String, n['line'] as int);
    if (k == 'id') {
      final base = (n['name'] as String).split('.').first;
      if (!declared.contains(base) && !consts.containsKey(base)) {
        err(main.name, n['line'] as int, "'$base' was not declared in this scope");
      }
    }
    if (k == 'call') {
      final name = n['name'] as String;
      if (name.contains('.')) {
        final base = name.split('.').first;
        if (base == 'RoboCore') {
          if (!libsIn.contains('robocore')) {
            err(main.name, n['line'] as int, "'RoboCore' has not been declared. Add #include <RoboCore.h> at the top of the sketch.");
          }
        } else if (base != 'Serial' && base != 'Wire' && !declared.contains(base)) {
          err(main.name, n['line'] as int, "'$base' was not declared in this scope");
        }
      } else if (!builtinFns.contains(name) && !fns.containsKey(name) && !castTypes.contains(name) && !declared.contains(name)) {
        if (espFns.contains(name) && b.arch != 'esp32') {
          err(main.name, n['line'] as int, "'$name' is only available on ESP32 boards");
        } else if (!espFns.contains(name)) {
          err(main.name, n['line'] as int, "'$name' was not declared in this scope");
        }
      }
    }
  });
  var strBytes = 0;
  walk(prog, (n) {
    if (n['k'] == 'str') strBytes += (n['v'] as String).length + 1;
  });
  final esp = b.arch == 'esp32';
  final size = b.base + toks.length * b.per + libsIn.length * (esp ? 9200 : 640);
  var globalsCount = 0;
  for (final d in prog['globals'] as List) {
    globalsCount += (d['items'] as List).length;
  }
  final ram = b.rbase + globalsCount * (esp ? 12 : 2) + strBytes + libsIn.length * (esp ? 180 : 40);
  errors.sort((a, c) => a.line.compareTo(c.line));
  return CompileResult(
    errors: errors.take(12).toList(),
    prog: prog,
    defines: defines,
    size: size,
    ram: ram,
    board: b,
    tokens: toks.length,
    extraConsts: extra,
  );
}

/// L-04: the message for a library the sketch includes but this device has not installed.
String notInstalled(String library) => '$library is not installed. Install it in Libraries.';

/// The optional libraries [files] #include that are not installed here. Checked before a compile on the
/// server too, which has every library: Libraries decides what a sketch may use.
List<Problem> missingLibraries(List<SourceFile> files, Set<String> installedLibs) {
  final out = <Problem>[];
  for (final f in files) {
    final lines = f.content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final inc = _includeRe.firstMatch(lines[i]);
      if (inc == null || inc.group(1) == '"') continue;
      final h = inc.group(2)!.trim();
      final lib = kLibs.where((l) => l.h == (kHeaderAlias[h] ?? h)).firstOrNull;
      if (lib != null && lib.kind == 'opt' && !installedLibs.contains(lib.id)) out.add(Problem(f.name, i + 1, notInstalled(lib.name)));
    }
  }
  return out;
}
