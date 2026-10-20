// The simulated RoboCore board: pins, LEDs, motors, sensors and serial I/O.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/catalog.dart';
import '../engine/compiler.dart';
import '../engine/interpreter.dart';

/// The preview board's sensors that the student can hold at a value (PB-01).
enum SimSensor { sonar, line, tilt, battery }

class SimBoard extends ChangeNotifier implements BoardIO {
  SimBoard({required this.onSerial, required this.onNote});

  /// Called for each complete line the sketch prints (dir: out | err | sys).
  final void Function(String text, String dir) onSerial;

  /// Called once per unsupported function, for the Output panel.
  final void Function(String text) onNote;

  final _rnd = math.Random();
  final _clock = Stopwatch();
  StopToken? _tok;
  Timer? _toneTimer;

  String boardId = 'v2';
  String name = '';
  bool running = false;
  int led = 0;
  List<int>? rgbColor;
  int? toneHz;
  List<int> motorSpeeds = [0, 0];
  int? servoAngle;
  final Map<int, int> pins = {};
  final Map<int, int> modes = {};
  bool user = false;
  bool readsSerial = false;
  double _dist = 42, _lineT = 0, _analog = 1800;

  /// Readings held at a value from the preview board; the others are simulated. Kept across runs.
  final Map<SimSensor, double> held = {};

  void hold(SimSensor k, double? v) {
    if (v == null) {
      held.remove(k);
    } else {
      held[k] = v;
    }
    _changed();
  }

  /// What a sensor reads now, for the preview board's readings (no noise, and reading it changes nothing).
  double reading(SimSensor k) =>
      held[k] ??
      switch (k) {
        SimSensor.sonar => (_dist * 10).round() / 10,
        SimSensor.line => _linePos(),
        SimSensor.tilt => _tiltAuto(),
        SimSensor.battery => _voltsAuto(),
      };

  double _linePos() => (math.sin(_lineT) * .7).clamp(-1.0, 1.0);
  double _tiltAuto() => 2 + math.sin(millis() / 2500) * 6;
  double _voltsAuto() => 3.92 - millis() / 3600000 * .05;

  // The robot's wheels and heading, worked out from the motor speeds over time (SimBoardPhysics).
  final List<double> _turns = [0, 0];
  double _heading = 0;
  int _physMs = 0;

  void _physics() {
    final now = millis();
    final dt = (now - _physMs) / 1000.0;
    _physMs = now;
    if (dt <= 0) return;
    const tps = SimBoardPhysics.turnsPerSecond;
    final l = motorSpeeds[0] / 100 * tps, r = motorSpeeds[1] / 100 * tps;
    _turns[0] += l * dt;
    _turns[1] += r * dt;
    _heading += (l - r) * SimBoardPhysics.wheelCm / SimBoardPhysics.trackCm * 180 / math.pi * dt;
  }
  String _lineBuf = '';
  String _inQ = '';
  final Set<String> _skipped = {};

  BoardDef get board => kBoards[boardId] ?? kBoards['v2']!;
  int get uptimeSeconds => (_clock.elapsedMilliseconds / 1000).round();

  void _changed() => notifyListeners();

  void reset() {
    led = 0;
    rgbColor = null;
    toneHz = null;
    motorSpeeds = [0, 0];
    servoAngle = null;
    _turns[0] = _turns[1] = 0;
    _heading = 0;
    _physMs = 0;
    pins.clear();
    modes.clear();
    _lineBuf = '';
    _inQ = '';
    readsSerial = false;
    _skipped.clear();
    _toneTimer?.cancel();
  }

  void stop() {
    _tok?.stop = true;
    _tok = null;
    running = false;
    _toneTimer?.cancel();
    toneHz = null;
    _changed();
  }

  /// Runs a compiled sketch until [stop] is called or it hits an error.
  Future<RuntimeErr?> run(CompileResult info, String sketchName) async {
    stop();
    reset();
    final tok = StopToken();
    _tok = tok;
    running = true;
    boardId = info.board.id;
    name = sketchName;
    _clock
      ..reset()
      ..start();
    _changed();
    final err = await Interpreter(info, this, tok).run();
    if (identical(_tok, tok)) {
      running = false;
      _tok = null;
      toneHz = null;
      _changed();
    }
    return err;
  }

  void queueInput(String text) {
    if (running) _inQ += text;
  }

  void setUser(bool down) {
    user = down;
    _changed();
  }

  // ---- BoardIO ----
  @override
  int get boardLed => board.led;
  @override
  bool get userPressed => user;
  @override
  String get inQ => _inQ;
  @override
  set inQ(String v) => _inQ = v;
  @override
  void markReadsSerial() => readsSerial = true;
  @override
  int millis() => _clock.elapsedMilliseconds;

  @override
  void pinMode(int pin, int mode) {
    modes[pin] = mode;
    if (mode == 1 && pin != board.led && !pins.containsKey(pin)) {
      pins[pin] = 0;
      _changed();
    }
  }

  @override
  int? pinModeOf(int pin) => modes[pin];

  @override
  void digitalWrite(int pin, int v) {
    if (pin == board.led) {
      led = v;
      // The RoboCore V2 has no plain LED: LED_BUILTIN is the RGB LED, and HIGH lights it white.
      if (board.id == 'v2') rgbColor = v != 0 ? const [255, 255, 255] : const [0, 0, 0];
    } else {
      pins[pin] = v;
    }
    _changed();
  }

  @override
  int digitalRead(int pin) {
    if (board.id == 'v2') {
      // USER (IO42) and BOOT (IO0) have pull-ups on the board and read LOW when pressed.
      if (pin == RoboCoreV2Pins.userButton || modes[pin] == 2) return user ? 0 : 1;
      if (pin == RoboCoreV2Pins.bootButton) return 1;
    } else if (modes[pin] == 2 || pin == 0) {
      return user ? 0 : 1;
    }
    return (pins[pin] ?? 0) != 0 ? 1 : 0;
  }

  @override
  int analogRead() {
    final max = board.arch == 'avr' ? 1023.0 : 4095.0;
    _analog = (_analog + (_rnd.nextDouble() - .5) * 260).clamp(0.0, max).toDouble();
    return _analog.round();
  }

  @override
  void tone(num freq, num? ms) {
    toneHz = freq > 0 ? freq.round() : null;
    _toneTimer?.cancel();
    if (freq > 0 && ms != null && ms > 0) {
      _toneTimer = Timer(Duration(milliseconds: ms.round()), () {
        toneHz = null;
        _changed();
      });
    }
    _changed();
  }

  @override
  void noTone() => tone(0, null);

  @override
  void rgb(int r, int g, int b) {
    rgbColor = [r.clamp(0, 255).toInt(), g.clamp(0, 255).toInt(), b.clamp(0, 255).toInt()];
    _changed();
  }

  @override
  void motors(num l, num r) {
    _physics();
    motorSpeeds = [l.clamp(-100, 100).round(), r.clamp(-100, 100).round()];
    _changed();
  }

  @override
  num wheelTurns(int side) {
    _physics();
    return _turns[side == 0 ? 0 : 1];
  }

  @override
  num heading() {
    _physics();
    return _heading;
  }

  @override
  void servo(num a) {
    servoAngle = a.clamp(0, 180).round();
    _changed();
  }

  @override
  num distance() {
    final h = held[SimSensor.sonar];
    if (h != null) return _dist = h;
    final fwd = (motorSpeeds[0] + motorSpeeds[1]) / 2;
    final turning = motorSpeeds[0] * motorSpeeds[1] < 0;
    var d = _dist;
    if (turning) {
      d += 7 + _rnd.nextDouble() * 4;
    } else if (fwd > 0) {
      d -= fwd * .05 + _rnd.nextDouble() * 1.5;
    } else {
      d += (45 - d) * .08;
    }
    d += (_rnd.nextDouble() - .5) * 2.4;
    if (d < 5) d = 5 + _rnd.nextDouble() * 3;
    _dist = d.clamp(4.0, 180.0).toDouble();
    return (_dist * 10).round() / 10;
  }

  @override
  num lineRead() {
    final h = held[SimSensor.line];
    if (h != null) return h;
    _lineT += .18;
    final v = _linePos() + (_rnd.nextDouble() - .5) * .2;
    return (v.clamp(-1.0, 1.0) * 100).round() / 100;
  }

  @override
  num temperature() {
    final t = millis();
    return ((24.6 + math.sin(t / 9000) * .6 + (_rnd.nextDouble() - .5) * .2) * 10).round() / 10;
  }

  @override
  num batteryVolts() => held[SimSensor.battery] ?? ((_voltsAuto() + (_rnd.nextDouble() - .5) * .02) * 100).round() / 100;

  @override
  num tilt() => held[SimSensor.tilt] ?? ((_tiltAuto() + (_rnd.nextDouble() - .5)) * 10).round() / 10;

  void _splitLines() {
    var k = _lineBuf.indexOf('\n');
    while (k >= 0) {
      var line = _lineBuf.substring(0, k);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      onSerial(line, 'out');
      _lineBuf = _lineBuf.substring(k + 1);
      k = _lineBuf.indexOf('\n');
    }
  }

  @override
  void serialWrite(String s) {
    _lineBuf += s;
    _splitLines();
  }

  @override
  void serialFlushLine() {
    _splitLines();
    onSerial(_lineBuf, 'out');
    _lineBuf = '';
  }

  @override
  void skipped(String fn) {
    if (_skipped.add(fn)) onNote('Simulator note: $fn() has no effect in the preview board.');
  }
}
