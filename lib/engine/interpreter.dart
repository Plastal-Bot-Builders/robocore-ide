// Runs a parsed sketch against a simulated board.
import 'dart:async';
import 'dart:math' as math;

import '../data/catalog.dart';
import 'compiler.dart';
import 'lexer.dart';
import 'parser.dart';

class RuntimeErr implements Exception {
  final int? line;
  final String msg;
  RuntimeErr(this.line, this.msg);
}

class _Stop implements Exception {
  const _Stop();
}

class _Brk implements Exception {
  const _Brk();
}

class _Cont implements Exception {
  const _Cont();
}

class _Ret implements Exception {
  final dynamic value;
  const _Ret(this.value);
}

const _stop = _Stop();
const _brk = _Brk();
const _cont = _Cont();

class StopToken {
  bool stop = false;
}

/// What the interpreter can do to the (simulated or real) board.
/// The simulated robot: an XRP wheel turns 1.5 times a second at full speed and goes 18.8 cm a turn;
/// the wheels are 15.5 cm apart.
class SimBoardPhysics {
  static const turnsPerSecond = 1.5, wheelCm = 18.8, trackCm = 15.5;
}

abstract class BoardIO {
  int get boardLed;
  bool get userPressed;
  String get inQ;
  set inQ(String v);
  void markReadsSerial();
  int millis();
  void pinMode(int pin, int mode);
  int? pinModeOf(int pin);
  void digitalWrite(int pin, int v);
  int digitalRead(int pin);
  int analogRead();
  void tone(num freq, num? ms);
  void noTone();
  void rgb(int r, int g, int b);
  void motors(num l, num r);
  void servo(num a);
  num distance();
  num lineRead();
  num temperature();
  num tilt();

  /// Battery pack voltage (RoboCore::batteryVolts()).
  num batteryVolts();

  /// How far each wheel (0 = left, 1 = right) has turned since the sketch started, in turns; forward is positive.
  num wheelTurns(int side);

  /// The robot's heading since the sketch started, in degrees; turning right counts up.
  num heading();
  void serialWrite(String s);
  void serialFlushLine();
  void skipped(String name);
}

final _flt = RegExp(r'\b(float|double)\b');
final _intT = RegExp(r'\b(int|long|short|byte|char|unsigned|word|size_t|u?int(8|16|32|64)_t)\b');
final _boolT = RegExp(r'\bbool(ean)?\b');

String jsStr(dynamic v) {
  if (v == null) return '';
  if (v is double) {
    if (v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }
  return '$v';
}

bool truthy(dynamic v) {
  if (v == null) return false;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

num _asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim()) ?? 0;
  return 0;
}

int _asInt(dynamic v) {
  final n = _asNum(v);
  if (n is int) return n;
  if (!n.isFinite) return 0;
  return n.truncate();
}

dynamic coerce(String? t, dynamic v) {
  if (t == null || t.isEmpty) return v;
  if (t.contains('*')) return v; // const char *name: keep the text
  if (t == 'String' || t == 'const String') return v is num ? jsStr(v) : jsStr(v ?? '');
  if (_boolT.hasMatch(t)) return truthy(v) ? 1 : 0;
  if (_flt.hasMatch(t)) return _asNum(v).toDouble();
  if (_intT.hasMatch(t)) {
    if (v is String) return v.isEmpty ? 0 : v.codeUnitAt(0);
    return _asInt(v);
  }
  return v;
}

class _Ref {
  dynamic v;
  final String t;
  final bool arr, c;
  _Ref(this.v, this.t, {this.arr = false, this.c = false});
}

typedef Scope = List<Map<String, _Ref>>;

class Interpreter {
  /// How deep function calls may nest before the sketch is stopped (a real ESP32 would crash
  /// with a stack overflow; the preview stops cleanly and says why).
  static const maxCallDepth = 200;

  final CompileResult info;
  final BoardIO io;
  final StopToken tok;
  final Map<String, num> consts;
  final Map<String, _Ref> g = {};
  final Map<String, Node> fns;
  final math.Random _rnd = math.Random();
  int slept = 0;
  int _steps = 0;
  int _depth = 0;

  Interpreter(this.info, this.io, this.tok)
      : consts = {...baseConsts(info.board), ...info.extraConsts},
        fns = (info.prog!['fns'] as Map).cast<String, Node>();

  Future<void> sleep(num ms) async {
    slept++;
    _steps = 0;
    final end = io.millis() + ms;
    while (true) {
      if (tok.stop) throw _stop;
      final left = end - io.millis();
      if (left <= 0) break;
      await Future<void>.delayed(Duration(milliseconds: math.min(40, left.ceil())));
    }
    if (tok.stop) throw _stop;
  }

  Future<void> _tick() async {
    if (tok.stop) throw _stop;
    if (++_steps > 3000) {
      _steps = 0;
      await Future<void>.delayed(Duration.zero);
      if (tok.stop) throw _stop;
    }
  }

  _Ref? _look(String name, Scope sc) {
    for (final m in sc) {
      final r = m[name];
      if (r != null) return r;
    }
    return null;
  }

  bool _isObjType(String t) => t
      .split(RegExp(r'\s+'))
      .any((w) => w.isNotEmpty && w != '*' && w != '&' && !qualifiers.contains(w) && !primTypes.contains(w));

  bool _isFloat(Node? n, Scope sc) {
    if (n == null) return false;
    switch (n['k']) {
      case 'num':
        return n['f'] == true;
      case 'id':
        final r = _look(n['name'] as String, sc);
        return r != null && _flt.hasMatch(r.t);
      case 'cast':
        return _flt.hasMatch(n['to'] as String);
      case 'call':
        final nm = n['name'] as String;
        return RegExp(r'(distanceCm|temperature|tiltDeg|toFloat|batteryVolts|accel[XYZ]|gyro[XYZ]|positionDeg|speedPercent|yawDeg|pitchDeg|rollDeg|'
                r'\.timer|\.angle|\.left|\.centre|\.right)$')
                .hasMatch(nm) ||
            nm == 'line.read';
      case 'bin':
        return _isFloat(n['a'] as Node?, sc) || _isFloat(n['b'] as Node?, sc);
      case 'un':
        return _isFloat(n['a'] as Node?, sc);
      case 'tern':
        return _isFloat(n['a'] as Node?, sc) || _isFloat(n['b'] as Node?, sc);
    }
    return false;
  }

  Future<void> _declare(String type, Node it, Map<String, _Ref> map, Scope sc) async {
    final c = RegExp(r'\bconst\b').hasMatch(type);
    final name = it['name'] as String;
    if (it['arr'] == true) {
      final list = (it['list'] as List?)?.cast<Node>();
      final size = it['size'] != null ? _asInt(await ev(it['size'] as Node, sc)) : (list?.length ?? 0);
      final arr = List<dynamic>.filled(math.max(0, size), type == 'String' ? '' : 0, growable: false);
      if (list != null) {
        for (var i = 0; i < list.length && i < arr.length; i++) {
          arr[i] = coerce(type, await ev(list[i], sc));
        }
      }
      map[name] = _Ref(arr, type, arr: true, c: c);
      return;
    }
    if (_isObjType(type) && !RegExp(r'^(const\s+)?String$').hasMatch(type)) {
      map[name] = _Ref(<String, dynamic>{'obj': type}, type, c: c);
      return;
    }
    final dynamic v = it['init'] != null ? await ev(it['init'] as Node, sc) : (type == 'String' ? '' : 0);
    map[name] = _Ref(coerce(type, v), type, c: c);
  }

  Future<dynamic> _assign(Node t, dynamic v, Scope sc) async {
    if (t['k'] == 'id') {
      final r = _look(t['name'] as String, sc);
      if (r == null) throw RuntimeErr(t['line'] as int?, "'${t['name']}' was not declared in this scope");
      if (r.c) throw RuntimeErr(t['line'] as int?, "assignment of read-only variable '${t['name']}'");
      r.v = coerce(r.t, v);
      return r.v;
    }
    if (t['k'] == 'idx') {
      final arr = await ev(t['a'] as Node, sc);
      final i = _asInt(await ev(t['i'] as Node, sc));
      if (arr is! List) throw RuntimeErr(t['line'] as int?, 'subscripted value is not an array');
      final a = t['a'] as Node;
      final base = a['k'] == 'id' ? _look(a['name'] as String, sc) : null;
      if (i >= 0 && i < arr.length) arr[i] = coerce(base?.t, v);
      return v;
    }
    throw RuntimeErr(t['line'] as int?, 'lvalue required');
  }

  dynamic _arith(String o, dynamic c, dynamic v, bool isF, int? line) {
    switch (o) {
      case '+':
        if (c is String || v is String) return jsStr(c) + jsStr(v);
        return _asNum(c) + _asNum(v);
      case '-':
        return _asNum(c) - _asNum(v);
      case '*':
        return _asNum(c) * _asNum(v);
      case '/':
        final b = _asNum(v), a = _asNum(c);
        if (b == 0) {
          if (isF) return a / b;
          throw RuntimeErr(line, 'division by zero');
        }
        return isF ? a / b : (a / b).truncate();
      case '%':
        final b = _asNum(v);
        return b == 0 ? 0 : _asNum(c).remainder(b);
      case '|':
        return _asInt(c) | _asInt(v);
      case '&':
        return _asInt(c) & _asInt(v);
      case '^':
        return _asInt(c) ^ _asInt(v);
      case '<<':
        return _asInt(c) << _asInt(v);
      case '>>':
        return _asInt(c) >> _asInt(v);
    }
    return 0;
  }

  int _cmp(dynamic a, dynamic b) {
    if (a is String && b is String) return a.compareTo(b);
    return _asNum(a).compareTo(_asNum(b));
  }

  bool _eq(dynamic a, dynamic b) {
    if (a is num && b is num) return a == b;
    if (a is String && b is String) return a == b;
    if (a is String || b is String) return jsStr(a) == jsStr(b);
    return identical(a, b);
  }

  Future<dynamic> ev(Node n, Scope sc) async {
    await _tick();
    switch (n['k']) {
      case 'num':
        return n['v'];
      case 'str':
        return n['v'];
      case 'id':
        {
          final name = n['name'] as String;
          final r = _look(name, sc);
          if (r != null) return r.v;
          final c = consts[name];
          if (c != null) return c;
          throw RuntimeErr(n['line'] as int?, "'$name' was not declared in this scope");
        }
      case 'un':
        {
          final a = await ev(n['a'] as Node, sc);
          switch (n['op']) {
            case '-':
              return -_asNum(a);
            case '!':
              return truthy(a) ? 0 : 1;
            case '~':
              return ~_asInt(a);
          }
          return _asNum(a);
        }
      case 'cast':
        return coerce(n['to'] == 'boolean' ? 'bool' : n['to'] as String, await ev(n['a'] as Node, sc));
      case 'tern':
        return truthy(await ev(n['c'] as Node, sc)) ? ev(n['a'] as Node, sc) : ev(n['b'] as Node, sc);
      case 'bin':
        {
          final op = n['op'] as String;
          if (op == '&&') return (truthy(await ev(n['a'] as Node, sc)) && truthy(await ev(n['b'] as Node, sc))) ? 1 : 0;
          if (op == '||') return (truthy(await ev(n['a'] as Node, sc)) || truthy(await ev(n['b'] as Node, sc))) ? 1 : 0;
          final a = await ev(n['a'] as Node, sc), b = await ev(n['b'] as Node, sc);
          switch (op) {
            case '<':
              return _cmp(a, b) < 0 ? 1 : 0;
            case '>':
              return _cmp(a, b) > 0 ? 1 : 0;
            case '<=':
              return _cmp(a, b) <= 0 ? 1 : 0;
            case '>=':
              return _cmp(a, b) >= 0 ? 1 : 0;
            case '==':
              return _eq(a, b) ? 1 : 0;
            case '!=':
              return _eq(a, b) ? 0 : 1;
          }
          final isF = _isFloat(n['a'] as Node?, sc) || _isFloat(n['b'] as Node?, sc);
          return _arith(op, a, b, isF, n['line'] as int?);
        }
      case 'asg':
        {
          var v = await ev(n['v'] as Node, sc);
          final op = n['op'] as String;
          if (op != '=') {
            final c = await ev(n['t'] as Node, sc);
            final o = op.substring(0, op.length - 1);
            final isF = _isFloat(n['t'] as Node?, sc) || _isFloat(n['v'] as Node?, sc);
            if (o == '/' && _asNum(v) == 0) {
              v = 0;
            } else {
              v = _arith(o, c, v, isF, n['line'] as int?);
            }
          }
          return _assign(n['t'] as Node, v, sc);
        }
      case 'pre':
        {
          final v = _asNum(await ev(n['t'] as Node, sc)) + (n['op'] == '++' ? 1 : -1);
          return _assign(n['t'] as Node, v, sc);
        }
      case 'post':
        {
          final v = _asNum(await ev(n['t'] as Node, sc));
          await _assign(n['t'] as Node, v + (n['op'] == '++' ? 1 : -1), sc);
          return v;
        }
      case 'idx':
        {
          final a = await ev(n['a'] as Node, sc);
          final i = _asInt(await ev(n['i'] as Node, sc));
          if (a is String) return (i >= 0 && i < a.length) ? a.codeUnitAt(i) : 0;
          if (a is! List) throw RuntimeErr(n['line'] as int?, 'subscripted value is not an array');
          return (i >= 0 && i < a.length) ? (a[i] ?? 0) : 0;
        }
      case 'call':
        return _call(n, sc);
    }
    return 0;
  }

  String _fmt(dynamic v, dynamic digits, Node? node, Scope sc) {
    if (v is String) return v;
    if (v is! num) return '';
    final isInt = v is int || (v.isFinite && v == v.truncateToDouble());
    final fl = _isFloat(node, sc) || !isInt;
    if (fl) {
      final d = digits == null ? 2 : _asInt(digits).clamp(0, 8).toInt();
      return v.toDouble().toStringAsFixed(d);
    }
    final iv = v.toInt();
    if (digits == 16) return iv.toRadixString(16).toUpperCase();
    if (digits == 2) return iv.toRadixString(2);
    if (digits == 8) return iv.toRadixString(8);
    return '$iv';
  }

  Future<dynamic> _call(Node n, Scope sc) async {
    final nm = n['name'] as String;
    final argNodes = (n['args'] as List).cast<Node>();
    final a = <dynamic>[];
    for (final x in argNodes) {
      a.add(await ev(x, sc));
    }
    dynamic arg(int i) => i < a.length ? a[i] : 0;
    num argN(int i) => _asNum(arg(i));
    Node? argNode(int i) => i < argNodes.length ? argNodes[i] : null;
    dynamic digitsArg() => a.length > 1 ? a[1] : null;

    final user = fns[nm];
    if (user != null) return callFn(user, a);

    final dot = nm.lastIndexOf('.');
    final obj = dot > 0 ? nm.substring(0, dot) : null;
    final meth = dot > 0 ? nm.substring(dot + 1) : nm;
    if (obj == null) {
      switch (nm) {
        case 'pinMode':
          io.pinMode(_asInt(arg(0)), _asInt(arg(1)));
          return 0;
        case 'digitalWrite':
          io.digitalWrite(_asInt(arg(0)), truthy(arg(1)) ? 1 : 0);
          return 0;
        case 'digitalRead':
          return io.digitalRead(_asInt(arg(0)));
        case 'analogRead':
          return io.analogRead();
        case 'analogWrite':
          io.digitalWrite(_asInt(arg(0)), argN(1) > 0 ? 1 : 0);
          return 0;
        case 'delay':
          await sleep(math.max(0, argN(0)));
          return 0;
        case 'delayMicroseconds':
        case 'yield':
        case 'randomSeed':
        case 'attachInterrupt':
        case 'detachInterrupt':
        case 'ledcAttach':
        case 'ledcWrite':
          return 0;
        case 'millis':
          return io.millis();
        case 'micros':
          return io.millis() * 1000;
        case 'random':
          if (a.length > 1) return (argN(0) + _rnd.nextDouble() * (argN(1) - argN(0))).floor();
          return (_rnd.nextDouble() * argN(0)).floor();
        case 'map':
          if (argN(2) == argN(1)) return argN(3);
          return ((argN(0) - argN(1)) * (argN(4) - argN(3)) / (argN(2) - argN(1)) + argN(3)).truncate();
        case 'constrain':
          return math.min(math.max(argN(0), argN(1)), argN(2));
        case 'abs':
          return argN(0).abs();
        case 'min':
          return math.min(argN(0), argN(1));
        case 'max':
          return math.max(argN(0), argN(1));
        case 'sqrt':
          return math.sqrt(argN(0));
        case 'pow':
          return math.pow(argN(0), argN(1));
        case 'sq':
          return argN(0) * argN(0);
        case 'sin':
          return math.sin(argN(0));
        case 'cos':
          return math.cos(argN(0));
        case 'floor':
          return argN(0).floor();
        case 'ceil':
          return argN(0).ceil();
        case 'round':
          return argN(0).round();
        case 'bitRead':
          return (_asInt(arg(0)) >> _asInt(arg(1))) & 1;
        case 'tone':
          io.tone(argN(1), a.length > 2 ? argN(2) : null);
          return 0;
        case 'noTone':
          io.noTone();
          return 0;
        case 'rgbLedWrite':
        case 'neopixelWrite':
          io.rgb(_asInt(arg(1)), _asInt(arg(2)), _asInt(arg(3)));
          return 0;
        case 'String':
          return a.isNotEmpty ? _fmt(a[0], digitsArg(), argNode(0), sc) : '';
      }
      if (castTypes.contains(nm)) return coerce(nm, arg(0));
      io.skipped(nm);
      return 0;
    }
    if (obj == 'RoboCore') return _roboCore(nm, meth, a);
    if (obj == 'Serial') {
      switch (meth) {
        case 'begin':
        case 'flush':
        case 'setTimeout':
          return 0;
        case 'print':
          io.serialWrite(_fmt(arg(0), digitsArg(), argNode(0), sc));
          return 0;
        case 'println':
          if (a.isNotEmpty) io.serialWrite(_fmt(a[0], digitsArg(), argNode(0), sc));
          io.serialFlushLine();
          return 0;
        case 'write':
          final v = arg(0);
          io.serialWrite(v is num ? String.fromCharCode(v.toInt()) : jsStr(v));
          return 0;
        case 'available':
          io.markReadsSerial();
          return io.inQ.length;
        case 'read':
          io.markReadsSerial();
          if (io.inQ.isEmpty) return -1;
          final c = io.inQ.codeUnitAt(0);
          io.inQ = io.inQ.substring(1);
          return c;
        case 'peek':
          return io.inQ.isEmpty ? -1 : io.inQ.codeUnitAt(0);
        case 'readString':
          io.markReadsSerial();
          final s = io.inQ;
          io.inQ = '';
          return s;
        case 'readStringUntil':
          io.markReadsSerial();
          final ch = String.fromCharCode(_asInt(arg(0)));
          final q = io.inQ;
          final k = q.indexOf(ch);
          if (k < 0) {
            io.inQ = '';
            return q;
          }
          io.inQ = q.substring(k + 1);
          return q.substring(0, k);
        case 'parseInt':
          io.markReadsSerial();
          final m = RegExp(r'-?\d+').firstMatch(io.inQ);
          if (m == null) {
            io.inQ = '';
            return 0;
          }
          io.inQ = io.inQ.substring(m.end);
          return int.parse(m.group(0)!);
      }
      io.skipped(nm);
      return 0;
    }
    final r = _look(obj, sc);
    if (r == null) throw RuntimeErr(n['line'] as int?, "'$obj' was not declared in this scope");
    final rv = r.v;
    if (rv is String) {
      switch (meth) {
        case 'length':
          return rv.length;
        case 'trim':
          r.v = rv.trim();
          return 0;
        case 'toInt':
          return int.tryParse(RegExp(r'^\s*-?\d+').stringMatch(rv)?.trim() ?? '') ?? 0;
        case 'toFloat':
          return double.tryParse(RegExp(r'^\s*-?\d*\.?\d+').stringMatch(rv)?.trim() ?? '') ?? 0.0;
        case 'equals':
          return rv == jsStr(arg(0)) ? 1 : 0;
        case 'toUpperCase':
          r.v = rv.toUpperCase();
          return 0;
        case 'toLowerCase':
          r.v = rv.toLowerCase();
          return 0;
        case 'indexOf':
          final x = arg(0);
          return rv.indexOf(x is num ? String.fromCharCode(x.toInt()) : jsStr(x));
        case 'startsWith':
          return rv.startsWith(jsStr(arg(0))) ? 1 : 0;
        case 'endsWith':
          return rv.endsWith(jsStr(arg(0))) ? 1 : 0;
        case 'charAt':
          final i = _asInt(arg(0));
          return (i >= 0 && i < rv.length) ? rv.codeUnitAt(i) : 0;
        case 'substring':
          final s = _asInt(arg(0)).clamp(0, rv.length).toInt();
          final e = a.length > 1 ? _asInt(arg(1)).clamp(s, rv.length).toInt() : rv.length;
          return rv.substring(s, e);
      }
      return 0;
    }
    final t = r.t;
    final o = rv is Map<String, dynamic> ? rv : <String, dynamic>{};
    num argD(int i, num def) => i < a.length ? _asNum(a[i]) : def;
    // "Just happened" checks remember the last answer in the object.
    bool edge(String key, bool now) {
      final was = o[key] == true;
      o[key] = now;
      return now && !was;
    }

    if (t.contains('RoboCoreDrive')) return _drive(o, nm, meth, a);
    if (t.contains('RoboCoreEdge')) {
      if (meth == 'rose') return edge('was', truthy(arg(0))) ? 1 : 0;
    } else if (t.contains('RoboCoreServos')) {
      final port = _asInt(argD(0, 1));
      switch (meth) {
        case 'write':
          final deg = argN(1).clamp(0, 180);
          o['s$port'] = deg;
          io.servo(deg);
          return 0;
        case 'angle':
          return o['s$port'] ?? (port >= 1 && port <= 4 ? 90 : 0);
        case 'release':
        case 'setPulseRange':
          return 0;
      }
    } else if (t.contains('RoboCoreMotors')) {
      final side = _asInt(argD(0, 0)) == 1 ? 1 : 0;
      final counts = kRoboCoreConsts['RC_COUNTS_PER_WHEEL_TURN']!;
      switch (meth) {
        case 'begin':
          return 1;
        case 'drive':
          _setMotors(argN(0), argN(1));
          return 0;
        case 'stop':
        case 'brake':
          if (a.isEmpty) {
            _setMotors(0, 0);
          } else {
            _setSide(side, 0);
          }
          return 0;
        case 'start':
          _setSide(side, argN(1));
          return 0;
        case 'run':
          await _runSide(side, argN(1), _asInt(argD(2, 1)), argD(3, 50));
          return 0;
        case 'positionDeg':
          return (io.wheelTurns(side) - _asNum(o['p$side'] ?? 0)) * 360;
        case 'resetPosition':
          o['p$side'] = io.wheelTurns(side);
          return 0;
        case 'speedPercent':
          return side == 0 ? _ml : _mr;
        case 'leftSpeed':
          return _ml;
        case 'rightSpeed':
          return _mr;
        case 'leftCount':
          return ((io.wheelTurns(0) - _asNum(o['e0'] ?? 0)) * counts).round();
        case 'rightCount':
          return ((io.wheelTurns(1) - _asNum(o['e1'] ?? 0)) * counts).round();
        case 'resetEncoders':
          o['e0'] = io.wheelTurns(0);
          o['e1'] = io.wheelTurns(1);
          return 0;
        case 'countsPerTurn':
          return counts;
        case 'fault':
        case 'setReversed':
        case 'setEncoderReversed':
        case 'setCountsPerTurn':
          return 0;
        case 'leftCurrentmA':
        case 'rightCurrentmA':
          return (side == 0 ? _ml : _mr).abs() * 4;
      }
    } else if (t.contains('LineSensor')) {
      // Darkness under each sensor, from the simulated line position (-1 left … 1 right).
      num dark(String which) {
        final pos = io.lineRead();
        return switch (which) {
          'left' => (-pos).clamp(0, 1),
          'right' => pos.clamp(0, 1),
          _ => (1 - pos.abs()).clamp(0, 1),
        };
      }
      bool onLine() => dark('left') > .5 || dark('centre') > .5 || dark('right') > .5;
      switch (meth) {
        case 'begin':
          return 1;
        case 'read':
          return io.lineRead();
        case 'left':
        case 'centre':
        case 'right':
          return dark(meth);
        case 'onLine':
          return onLine() ? 1 : 0;
        case 'justFound':
          return edge('found', onLine()) ? 1 : 0;
        case 'justLost':
          // "Lost" only after it was found.
          o['lost'] ??= true;
          return edge('lost', !onLine()) ? 1 : 0;
        case 'resetCalibration':
        case 'setDarkIsHigh':
          return 0;
      }
    } else if (t.contains('IMU')) {
      switch (meth) {
        case 'begin':
          return 1;
        case 'ok':
          return 1;
        case 'temperature':
          return io.temperature();
        case 'tiltDeg':
          return io.tilt();
        case 'yawDeg':
          return io.heading() - _asNum(o['yaw0'] ?? 0);
        case 'resetYaw':
          o['yaw0'] = io.heading();
          return 0;
        case 'pitchDeg':
          return io.tilt();
        case 'rollDeg':
          return 0;
        case 'isTilted':
          return io.tilt() > 30 ? 1 : 0;
        case 'isFlat':
          return io.tilt() < 10 ? 1 : 0;
        case 'isShaken':
          return 0;
        case 'justTilted':
          return edge('tilted', io.tilt() > 30) ? 1 : 0;
        case 'justFlat':
          o['flat'] ??= true;
          return edge('flat', io.tilt() < 10) ? 1 : 0;
        case 'justShaken':
          return 0;
        case 'setYawReversed':
        case 'update':
          return 0;
      }
    }
    switch (meth) {
      case 'begin':
        return 1; // sonar.begin() ... report success
      case 'attach':
      case 'detach':
      case 'init':
      case 'setBrightness':
      case 'show':
      case 'clear':
      case 'backlight':
        return 0;
      case 'distanceCm':
      case 'ping_cm':
        return io.distance();
      case 'lastEchoOk':
        return 1;
      case 'justCloserThan':
        return edge('close${argN(0)}', io.distance() < argN(0)) ? 1 : 0;
      case 'write':
        if (t.contains('Servo')) {
          io.servo(argN(0));
          return 0;
        }
        break;
    }
    io.skipped(nm);
    return 0;
  }

  // ---- The motors and the driving base (the IDE's Movement and Motors blocks)
  num _ml = 0, _mr = 0;

  void _setMotors(num l, num r) {
    _ml = l.clamp(-100, 100);
    _mr = r.clamp(-100, 100);
    io.motors(_ml, _mr);
  }

  void _setSide(int side, num pct) => side == 0 ? _setMotors(pct, _mr) : _setMotors(_ml, pct);

  /// One motor for an amount (unit: ROTATIONS 1, DEGREES 2, SECONDS 3), then stops it.
  Future<void> _runSide(int side, num amount, int unit, num pct) async {
    if (amount == 0) return;
    final dir = amount < 0 ? -1 : 1;
    final sp = pct.abs().clamp(5, 100);
    final secs = unit == 3 ? amount.abs() : (unit == 2 ? amount.abs() / 360 : amount.abs()) / (SimBoardPhysics.turnsPerSecond * sp / 100);
    _setSide(side, dir * sp);
    await sleep(secs * 1000);
    _setSide(side, 0);
  }

  /// robot.… (RoboCoreDrive): moves take as long as they would on the robot.
  Future<dynamic> _drive(Map<String, dynamic> o, String nm, String meth, List<dynamic> a) async {
    num argD(int i, num def) => i < a.length ? _asNum(a[i]) : def;
    final speed = _asNum(o['speed'] ?? 50), wheel = _asNum(o['wheel'] ?? SimBoardPhysics.wheelCm), track = _asNum(o['track'] ?? SimBoardPhysics.trackCm);
    num avgTurns() => (io.wheelTurns(0) + io.wheelTurns(1)) / 2;
    switch (meth) {
      case 'move':
        final amount = argD(0, 0), unit = _asInt(argD(1, 0));
        if (amount == 0) return 0;
        final dir = amount < 0 ? -1 : 1, sp = speed.clamp(5, 100);
        final turns = unit == 1 ? amount.abs() : (unit == 2 ? amount.abs() / 360 : amount.abs() / wheel);
        final secs = unit == 3 ? amount.abs() : turns / (SimBoardPhysics.turnsPerSecond * sp / 100);
        _setMotors(dir * sp, dir * sp);
        await sleep(secs * 1000);
        _setMotors(0, 0);
        return 0;
      case 'turn':
        final deg = argD(0, 0);
        if (deg == 0) return 0;
        final dir = deg < 0 ? -1 : 1, sp = speed.clamp(15, 60);
        final cmPerSec = sp / 100 * SimBoardPhysics.turnsPerSecond * SimBoardPhysics.wheelCm;
        final degPerSec = 2 * cmPerSec / SimBoardPhysics.trackCm * 180 / math.pi;
        _setMotors(dir * sp, -dir * sp);
        await sleep(deg.abs() / degPerSec * 1000);
        _setMotors(0, 0);
        return 0;
      case 'start':
        final d = argD(0, 1) < 0 ? -1 : 1;
        _setMotors(d * speed, d * speed);
        return 0;
      case 'steer':
        final st = argD(0, 0).clamp(-100, 100);
        _setMotors(st < 0 ? speed * (1 + st / 50) : speed, st > 0 ? speed * (1 - st / 50) : speed);
        return 0;
      case 'stop':
        _setMotors(0, 0);
        return 0;
      case 'setSpeed':
        o['speed'] = argD(0, 50).clamp(0, 100);
        return 0;
      case 'speed':
        return speed;
      case 'setWheelCm':
        if (argD(0, 0) > 0) o['wheel'] = argD(0, wheel);
        return 0;
      case 'setTrackCm':
        if (argD(0, 0) > 0) o['track'] = argD(0, track);
        return 0;
      case 'distanceCm':
        return (avgTurns() - _asNum(o['d0'] ?? 0)) * wheel;
      case 'resetDistance':
        o['d0'] = avgTurns();
        return 0;
    }
    io.skipped(nm);
    return 0;
  }

  // ---- RoboCore:: state (USER edge, timer, LED colour and brightness)
  bool _userWas = false;
  int _timer0 = 0;
  final Map<num, bool> _timerFired = {};
  double _bright = 1;
  List<int> _rgb = const [0, 0, 0];

  void _showRgb() => io.rgb((_rgb[0] * _bright).round(), (_rgb[1] * _bright).round(), (_rgb[2] * _bright).round());

  static const _melodies = <List<List<int>>>[
    [[523, 90], [659, 90], [784, 90], [1047, 180]], // power up
    [[1047, 90], [784, 90], [659, 90], [523, 180]], // power down
    [[784, 100], [1047, 220]], // success
    [[330, 180], [262, 320]], // error
    [[880, 150], [660, 150], [880, 150], [660, 150], [880, 150], [660, 150]], // alarm
  ];

  /// The RoboCore:: helpers from RoboCore.h.
  Future<dynamic> _roboCore(String nm, String meth, List<dynamic> a) async {
    num argN(int i, num def) => i < a.length ? _asNum(a[i]) : def;
    switch (meth) {
      case 'batteryVolts':
        return io.batteryVolts();
      case 'batteryPercent':
        final v = io.batteryVolts();
        return v < 2.5 ? 0 : ((v - 3.3) / (4.15 - 3.3) * 100).clamp(0, 100).round();
      case 'userPressed':
        return io.userPressed ? 1 : 0;
      case 'userJustPressed':
        final now = io.userPressed, fired = now && !_userWas;
        _userWas = now;
        return fired ? 1 : 0;
      case 'waitForUser':
        final timeout = argN(0, 0);
        final start = io.millis();
        while (!io.userPressed) {
          if (timeout > 0 && io.millis() - start >= timeout) return 0;
          await sleep(5);
        }
        await sleep(20);
        while (io.userPressed) {
          await sleep(5);
        }
        await sleep(20);
        return 1;
      case 'beep':
        final ms = argN(1, 80);
        io.tone(argN(0, 2000), ms);
        await sleep(ms);
        return 0;
      case 'melody':
        final tune = _melodies[_asInt(argN(0, 0)).clamp(0, _melodies.length - 1)];
        for (final n in tune) {
          io.tone(n[0], n[1]);
          await sleep(n[1] + 30);
        }
        return 0;
      case 'rgb':
        _rgb = [_asInt(argN(0, 0)), _asInt(argN(1, 0)), _asInt(argN(2, 0))];
        _showRgb();
        return 0;
      case 'ledBrightness':
        _bright = argN(0, 100).clamp(0, 100) / 100;
        _showRgb();
        return 0;
      case 'timer':
        return (io.millis() - _timer0) / 1000.0;
      case 'resetTimer':
        _timer0 = io.millis();
        _timerFired.clear();
        return 0;
      case 'timerPassed':
        final s = argN(0, 0);
        if (_timerFired[s] == true || (io.millis() - _timer0) / 1000.0 < s) return 0;
        _timerFired[s] = true;
        return 1;
      case 'stopProgram':
        // Motors and sound off; the sketch ends here, as the robot would sit still until RESET.
        _setMotors(0, 0);
        io.noTone();
        throw _stop;
    }
    io.skipped(nm);
    return 0;
  }

  Future<void> ex(Node n, Scope sc) async {
    switch (n['k']) {
      case 'nop':
        return;
      case 'blk':
        {
          final inner = <Map<String, _Ref>>[{}, ...sc];
          for (final s in (n['body'] as List).cast<Node>()) {
            await ex(s, inner);
          }
          return;
        }
      case 'decl':
        for (final it in (n['items'] as List).cast<Node>()) {
          await _declare(n['type'] as String, it, sc[0], sc);
        }
        return;
      case 'ex':
        await ev(n['e'] as Node, sc);
        return;
      case 'if':
        if (truthy(await ev(n['c'] as Node, sc))) {
          await ex(n['a'] as Node, sc);
        } else if (n['b'] != null) {
          await ex(n['b'] as Node, sc);
        }
        return;
      case 'while':
        while (truthy(await ev(n['c'] as Node, sc))) {
          try {
            await ex(n['body'] as Node, sc);
          } on _Brk {
            break;
          } on _Cont {
            continue;
          }
        }
        return;
      case 'do':
        do {
          try {
            await ex(n['body'] as Node, sc);
          } on _Brk {
            break;
          } on _Cont {
            // fall through to the condition
          }
        } while (truthy(await ev(n['c'] as Node, sc)));
        return;
      case 'for':
        {
          final s2 = <Map<String, _Ref>>[{}, ...sc];
          final init = n['init'] as Node?;
          if (init != null) {
            if (init['k'] == 'decl') {
              await ex(init, s2);
            } else {
              await ev(init['e'] as Node, s2);
            }
          }
          final c = n['c'] as Node?, step = n['step'] as Node?;
          while (c == null || truthy(await ev(c, s2))) {
            try {
              await ex(n['body'] as Node, s2);
            } on _Brk {
              break;
            } on _Cont {
              // next iteration
            }
            if (step != null) await ev(step, s2);
          }
          return;
        }
      case 'ret':
        throw _Ret(n['e'] != null ? await ev(n['e'] as Node, sc) : null);
      case 'brk':
        throw _brk;
      case 'cont':
        throw _cont;
    }
  }

  Future<dynamic> callFn(Node fn, List<dynamic> args) async {
    if (_depth >= maxCallDepth) {
      throw RuntimeErr(fn['line'] as int?,
          "stack overflow: calls to '${fn['name']}()' nested more than $maxCallDepth deep. A function that calls itself needs a way to stop.");
    }
    final m = <String, _Ref>{};
    final params = (fn['params'] as List).cast<Node>();
    for (var i = 0; i < params.length; i++) {
      final t = params[i]['type'] as String;
      m[params[i]['name'] as String] = _Ref(coerce(t, i < args.length ? args[i] : 0), t);
    }
    _depth++;
    try {
      await ex(fn['body'] as Node, [m, g]);
    } on _Ret catch (r) {
      return coerce(fn['type'] as String, r.value);
    } finally {
      _depth--;
    }
    return 0;
  }

  Future<void> init() async {
    for (final e in info.defines.entries) {
      if (e.value.v.isEmpty) continue;
      try {
        final node = Parser(lex(e.value.v)).soloExpr();
        final v = await ev(node, [g]);
        if (v is num) consts[e.key] = v;
      } on _Stop {
        rethrow;
      } catch (_) {
        // A #define that isn't a plain value is ignored by the simulator.
      }
    }
    for (final d in (info.prog!['globals'] as List).cast<Node>()) {
      for (final it in (d['items'] as List).cast<Node>()) {
        await _declare(d['type'] as String, it, g, [g]);
      }
    }
  }

  /// Runs setup() once, then loop() until stopped. Returns null when stopped
  /// normally, or the runtime error that ended the sketch.
  Future<RuntimeErr?> run() async {
    try {
      await init();
      await callFn(fns['setup']!, const []);
      while (!tok.stop) {
        final before = slept;
        await callFn(fns['loop']!, const []);
        if (slept == before) await sleep(16);
      }
    } on _Stop {
      return null;
    } on RuntimeErr catch (e) {
      if (tok.stop) return null;
      return e;
    } on _Brk {
      return RuntimeErr(null, 'break statement not within loop');
    } on _Cont {
      return RuntimeErr(null, 'continue statement not within a loop');
    } catch (e) {
      if (tok.stop) return null;
      return RuntimeErr(null, '$e');
    }
    return null;
  }
}

/// Board facts used by the simulator.
BoardDef boardFor(String id) => kBoards[id] ?? kBoards['v2']!;
