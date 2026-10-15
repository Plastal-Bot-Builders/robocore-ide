// Turns a blocks project into an Arduino sketch.
import '../data/catalog.dart';

num toNum(dynamic v) {
  if (v is num) return v.isFinite ? v : 0;
  final n = num.tryParse('${v ?? ''}'.trim());
  return (n == null || !n.isFinite) ? 0 : n;
}

int toInt(dynamic v) => toNum(v).truncate();

String varName(dynamic v) {
  var s = '${v ?? 'x'}'.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  if (s.isEmpty) s = 'x';
  if (RegExp(r'^\d').hasMatch(s)) s = 'v$s';
  return s;
}

String cstr(dynamic s) => '${s ?? ''}'.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

List<String> _uniq(Iterable<String> xs) {
  final seen = <String>{};
  return [for (final x in xs) if (seen.add(x)) x];
}

String genBlocks(String name, List<Map<String, dynamic>> setupBlocks, List<Map<String, dynamic>> loopBlocks) {
  final all = [...setupBlocks, ...loopBlocks];
  bool has(String t) => all.any((b) => b['t'] == t);
  final usesLed = has('led'),
      usesBtn = has('button'),
      usesMot = has('drive') || has('stop'),
      usesSonar = has('distance'),
      usesLine = has('linesens');
  final pins = _uniq(all.where((b) => b['t'] == 'pin').map((b) => '${toInt(b['pin'])}'));
  final tonePins = _uniq(all.where((b) => b['t'] == 'tone').map((b) => '${toInt(b['pin'])}'));
  final vars = _uniq(all.where((b) => const ['rand', 'setvar', 'change', 'printvar'].contains(b['t'])).map((b) => varName(b['v'])));
  final needSerial = all.any((b) => const ['print', 'printvar', 'distance', 'linesens'].contains(b['t'])) && !has('serial');

  final l = <String>['// $name', '// Made with blocks in RoboCore IDE.', ''];
  if (usesMot) l.add('#include <RoboCoreMotors.h>');
  if (usesSonar || usesLine) l.add('#include <RoboCoreSensors.h>');
  if (usesBtn) l.add('#define USER_BUTTON 0');
  final g = <String>[];
  if (usesMot) g.add('RoboCoreMotors motors;');
  if (usesSonar) g.add('Sonar sonar;');
  if (usesLine) g.add('LineSensor line;');
  for (final v in vars) {
    g.add('int $v = 0;');
  }
  if (l.length > 3) l.add('');
  if (g.isNotEmpty) l.addAll([...g, '']);

  List<String> st(Map<String, dynamic> b) {
    switch (b['t']) {
      case 'led':
        return ['digitalWrite(LED_BUILTIN, ${b['state'] == 'LOW' ? 'LOW' : 'HIGH'});'];
      case 'pin':
        return ['digitalWrite(${toInt(b['pin'])}, ${b['state'] == 'LOW' ? 'LOW' : 'HIGH'});'];
      case 'rgb':
        final c = kColors[b['color']] ?? kColors['off']!;
        return ['rgbLedWrite(RGB_BUILTIN, ${c.join(', ')});  // ${b['color']}'];
      case 'tone':
        {
          final ms = (toNum(b['secs']) * 1000).round();
          final t = ms < 0 ? 0 : ms;
          return ['tone(${toInt(b['pin'])}, ${kNotes[b['note']] ?? 262}, $t);  // ${b['note']}', 'delay($t);'];
        }
      case 'button':
        return ['while (digitalRead(USER_BUTTON) == HIGH) {', '  delay(10);', '}'];
      case 'wait':
        {
          final ms = (toNum(b['secs']) * (b['unit'] == 'ms' ? 1 : 1000)).round();
          return ['delay(${ms < 0 ? 0 : ms});'];
        }
      case 'rand':
        return ['${varName(b['v'])} = random(${toInt(b['a'])}, ${toInt(b['b']) + 1});'];
      case 'setvar':
        return ['${varName(b['v'])} = ${toInt(b['n'])};'];
      case 'change':
        return ['${varName(b['v'])} += ${toInt(b['n'])};'];
      case 'printvar':
        return ['Serial.println(${varName(b['v'])});'];
      case 'drive':
        final s = toNum(b['speed']).clamp(0, 100).truncate();
        final m = const {
              'forward': [1, 1],
              'backward': [-1, -1],
              'left': [-1, 1],
              'right': [1, -1],
            }[b['dir']] ??
            const [1, 1];
        return ['motors.drive(${m[0] * s}, ${m[1] * s});'];
      case 'stop':
        return ['motors.stop();'];
      case 'distance':
        return ['Serial.print("distance_cm=");', 'Serial.println(sonar.distanceCm(), 1);'];
      case 'linesens':
        return ['Serial.print("line=");', 'Serial.println(line.read(), 2);'];
      case 'serial':
        return ['Serial.begin(${b['baud'] == '9600' ? 9600 : 115200});'];
      case 'print':
        return ['Serial.println("${cstr(b['text'])}");'];
    }
    return [];
  }

  final setup = <String>[];
  if (needSerial) setup.add('Serial.begin(115200);');
  if (usesLed) setup.add('pinMode(LED_BUILTIN, OUTPUT);');
  for (final n in pins) {
    setup.add('pinMode($n, OUTPUT);');
  }
  for (final n in tonePins) {
    if (!pins.contains(n)) setup.add('pinMode($n, OUTPUT);');
  }
  if (usesBtn) setup.add('pinMode(USER_BUTTON, INPUT_PULLUP);');
  if (usesMot) setup.add('motors.begin();');
  if (usesSonar) setup.add('sonar.begin();');
  if (usesLine) setup.add('line.begin();');
  for (final b in setupBlocks) {
    setup.addAll(st(b));
  }
  final loop = <String>[];
  for (final b in loopBlocks) {
    loop.addAll(st(b));
  }
  l.addAll(['void setup() {', ...setup.map((s) => '  $s'), '}', '', 'void loop() {', ...loop.map((s) => '  $s'), '}', '']);
  return l.join('\n');
}
