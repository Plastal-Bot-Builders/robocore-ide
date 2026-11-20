// Cog's "blocks script": a stack of blocks written one per line, each as the block reads, with the blocks inside
// another indented (and "else" on its own line under its "if"):
//
//   forever
//     if is obstacle closer than 20 cm? then
//       stop moving
//     else
//       start moving forward
//
// parseBlockScript turns one into the rows the Cog panel draws and into Blockly's JSON for the workspace
// (web/robocore_editors.js, rcEditor.blocks.add). A line that is not a block from the catalogue stays a row of
// kind unknown and makes no block, so a wrong guess by the AI never becomes a wrong block.

enum RowKind { hat, block, open, middle, unknown }

/// One line of a script as the panel draws it. [cat] is the block's category (events, movement, motors, light,
/// sensors, control, operators, variables, pins), '' for a line that is not a block.
class BlockRow {
  const BlockRow(this.text, this.cat, this.depth, this.kind);
  final String text, cat;
  final int depth;
  final RowKind kind;
}

class BlockScript {
  const BlockScript(this.rows, this.stacks);
  final List<BlockRow> rows;

  /// Blockly's JSON for each stack, top block first (no positions: the editor finds a free place).
  final List<Map<String, dynamic>> stacks;

  /// Lines that are not a block.
  int get unknown => rows.where((r) => r.kind == RowKind.unknown).length;
  bool get isEmpty => stacks.isEmpty;
}

// ---------------------------------------------------------------- words

class _Tok {
  const _Tok(this.text, this.kind);
  final String text, kind; // num | str | sym | word
  String get low => text.toLowerCase();
}

final _tokRe = RegExp('"([^"]*)"|“([^”]*)”|(\\d+(?:\\.\\d+)?)|(<=|>=|!=|==|[≤≥≠()<>=+\\-*×÷/%°?,:])|([A-Za-z_][A-Za-z0-9_]*)');

List<_Tok> _tokens(String s) => [
      for (final m in _tokRe.allMatches(s))
        if (m.group(1) != null)
          _Tok(m.group(1)!, 'str')
        else if (m.group(2) != null)
          _Tok(m.group(2)!, 'str')
        else if (m.group(3) != null)
          _Tok(m.group(3)!, 'num')
        else if (m.group(4) != null)
          _Tok(m.group(4)!, 'sym')
        else
          _Tok(m.group(5)!, 'word')
    ];

// ---------------------------------------------------------------- patterns

sealed class _El {}

class _Lit extends _El {
  _Lit(this.alts, this.optional);
  final List<String> alts; // lower case
  final bool optional;
}

class _Menu extends _El {
  _Menu(this.name, this.options);
  final String name;
  final List<(List<String>, String)> options; // (the label's words in lower case, the field's value), longest first
}

class _Val extends _El {
  _Val(this.name, this.type);
  final String name, type; // num | bool | any
}

class _Num extends _El {
  _Num(this.name);
  final String name;
}

class _Name extends _El {
  _Name(this.name);
  final String name;
}

class _Pin extends _El {
  _Pin(this.name);
  final String name;
}

// Menus and endings several blocks share. A pattern names one as $side; "°" and "s" may be left out or spelled out.
const _menus = {
  r'$side': 'SIDE:left|right',
  r'$sensor': 'SENSOR:centre|center=centre|left|right',
  r'$state': 'STATE:tilted|shaken|flat',
  r'$dir': 'DIR:forward|forwards=forward|backward|backwards=backward',
  r'$note': 'NOTE:C4|D4|E4|F4|G4|A4|B4|C5|D5|E5|F5|G5|A5|C6',
};
const _endings = {r'$deg': '°/degrees/degree/deg~', r'$secs': 's/secs/sec/seconds/second~'};

/// A pattern's parts, separated by spaces: a word (word~ may be left out, a/b either), <NAME:a|b=VALUE> a menu,
/// [NAME] a number input, [NAME?] a yes / no input, [NAME*] any value, #NAME a typed number, @NAME a name,
/// ^NAME a pin.
List<_El> _compile(String pattern) {
  final out = <_El>[];
  for (var part in pattern.split(' ')) {
    if (part.isEmpty) continue;
    if (_menus.containsKey(part)) part = '<${_menus[part]}>';
    if (_endings.containsKey(part)) part = _endings[part]!;
    if (part.length > 2 && part.startsWith('<') && part.endsWith('>') && part.contains(':')) {
      final i = part.indexOf(':');
      final options = <(List<String>, String)>[];
      for (final o in part.substring(i + 1, part.length - 1).split('|')) {
        final eq = o.indexOf('=');
        final label = (eq > 0 ? o.substring(0, eq) : o).replaceAll('_', ' ');
        final value = eq > 0 ? o.substring(eq + 1).replaceAll('_', ' ') : label;
        options.add(([for (final t in _tokens(label)) t.low], value));
      }
      options.sort((a, b) => b.$1.length - a.$1.length);
      out.add(_Menu(part.substring(1, i), options));
    } else if (part.length > 2 && part.startsWith('[') && part.endsWith(']')) {
      final n = part.substring(1, part.length - 1);
      out.add(n.endsWith('?')
          ? _Val(n.substring(0, n.length - 1), 'bool')
          : n.endsWith('*')
              ? _Val(n.substring(0, n.length - 1), 'any')
              : _Val(n, 'num'));
    } else if (part.length > 1 && part.startsWith('#')) {
      out.add(_Num(part.substring(1)));
    } else if (part.length > 1 && part.startsWith('@')) {
      out.add(_Name(part.substring(1)));
    } else if (part.length > 1 && part.startsWith('^')) {
      out.add(_Pin(part.substring(1)));
    } else {
      final optional = part.length > 1 && part.endsWith('~');
      final body = optional ? part.substring(0, part.length - 1) : part;
      out.add(_Lit([for (final a in (body == '/' ? ['/'] : body.split('/'))) a.toLowerCase()], optional));
    }
  }
  return out;
}

class _Pat {
  _Pat(String pattern, this.type, this.cat, {this.kind = RowKind.block, this.out = '', this.fields = const {}, this.terminal = false})
      : els = _compile(pattern);
  final List<_El> els;
  final String type, cat;
  final RowKind kind;

  /// For a value block: num | bool | str.
  final String out;

  /// Fields the block always has.
  final Map<String, Object> fields;

  /// Nothing can follow it (stop program).
  final bool terminal;
}

// The catalogue as it reads on the blocks (web/robocore_editors.js, defineBlocks). The first pattern that reads the
// whole line wins, so a block with more words comes before one that starts the same way.
final _statements = <_Pat>[
  // Events
  _Pat('on start', 'rc_on_start', 'events', kind: RowKind.hat),
  _Pat('forever', 'rc_forever', 'events', kind: RowKind.hat),
  _Pat('when the~ USER button is pressed', 'rc_when_user', 'events', kind: RowKind.hat),
  _Pat('when an~ obstacle is closer than [CM] cm~', 'rc_when_closer', 'events', kind: RowKind.hat),
  _Pat('when the~ line is <STATE:found|lost>', 'rc_when_line', 'events', kind: RowKind.hat),
  _Pat(r'when the~ robot is $state', 'rc_when_tilt', 'events', kind: RowKind.hat),
  _Pat(r'when timer > [SECS] $secs', 'rc_when_timer', 'events', kind: RowKind.hat),
  _Pat('when I receive @MSG', 'rc_when_receive', 'events', kind: RowKind.hat),
  _Pat('when [COND?]', 'rc_when', 'events', kind: RowKind.hat),
  _Pat('broadcast @MSG', 'rc_broadcast', 'events'),
  // Movement
  _Pat(r'move $dir for [AMOUNT] <UNIT:cm|rotations|rotation=rotations|seconds|second=seconds|secs=seconds>', 'rc_move', 'movement'),
  _Pat(r'turn <DIR:right|left> for~ [DEG] $deg', 'rc_turn', 'movement'),
  _Pat('start moving ,~ steering [STEER]', 'rc_steer', 'movement'),
  _Pat(r'start moving $dir', 'rc_start_moving', 'movement'),
  _Pat('drive left [L] %~ right [R] %~', 'rc_drive_lr', 'movement'),
  _Pat('stop moving', 'rc_stop_moving', 'movement'),
  _Pat('set movement speed to [PCT] %~', 'rc_move_speed', 'movement'),
  _Pat('set 1 wheel turn to [CM] cm~', 'rc_wheel_size', 'movement'),
  // Motors
  _Pat(r'run $side motor for [AMOUNT] <UNIT:rotations|rotation=rotations|degrees|°=degrees|seconds|second=seconds|secs=seconds>', 'rc_motor_run',
      'motors'),
  _Pat(r'start $side motor at [PCT] %~', 'rc_motor_start', 'motors'),
  _Pat(r'stop $side motor', 'rc_motor_stop', 'motors'),
  _Pat(r'reset $side motor position', 'rc_motor_reset', 'motors'),
  _Pat(r'set servo <PORT:1|2|3|4> to [DEG] $deg', 'rc_servo_set', 'motors'),
  // Light & Sound
  _Pat('turn the~ LED <STATE:on=HIGH|off=LOW>', 'rc_led', 'light'),
  _Pat('set LED brightness to [PCT] %~', 'rc_led_brightness', 'light'),
  _Pat('set the~ LED to <COLOR:red|green|blue|yellow|purple|white|off>', 'rc_rgb', 'light'),
  _Pat(r'play beep $note for [SECS] $secs', 'rc_beep', 'light'),
  _Pat(r'start playing beep $note', 'rc_beep_start', 'light'),
  _Pat('play melody <TUNE:power_up|power_down|success|error|alarm>', 'rc_melody', 'light'),
  _Pat('stop sound', 'rc_sound_stop', 'light'),
  // Sensors
  _Pat('set yaw angle to 0', 'rc_reset_yaw', 'sensors'),
  _Pat('reset timer', 'rc_reset_timer', 'sensors'),
  _Pat('distance sensor on TRIG pin ^TRIG ECHO pin ^ECHO', 'rc_sonar_pins', 'sensors'),
  // Control
  _Pat('wait until [COND?]', 'rc_wait_until', 'control'),
  _Pat('wait #TIME <UNIT:secs|seconds=secs|second=secs|sec=secs|s=secs|ms>', 'rc_wait', 'control'),
  _Pat('repeat until [BOOL?]', 'rc_repeat_until', 'control', kind: RowKind.open),
  _Pat('repeat [TIMES] times/time~', 'controls_repeat_ext', 'control', kind: RowKind.open),
  _Pat('else if [IF?] then~', 'else_if', 'control', kind: RowKind.middle),
  _Pat('else', 'else', 'control', kind: RowKind.middle),
  _Pat('if [IF?] then~', 'controls_if', 'control', kind: RowKind.open),
  _Pat('stop program', 'rc_stop_program', 'control', terminal: true),
  // Pins & Serial
  _Pat('set pin ^PIN to <STATE:HIGH|LOW>', 'rc_pin', 'pins'),
  _Pat('start serial at <BAUD:115200|9600> baud~', 'rc_serial_begin', 'pins'),
  _Pat('print [VALUE*]', 'rc_print', 'pins'),
  // Variables (after every other "set …")
  _Pat('change @VAR by [DELTA]', 'math_change', 'variables'),
  _Pat('set @VAR to [VALUE*]', 'variables_set', 'variables'),
];

final _reporters = <_Pat>[
  _Pat('distance moved (~ cm~ )~', 'rc_distance_moved', 'movement', out: 'num'),
  _Pat('distance (~ cm~ )~', 'rc_distance', 'sensors', out: 'num'),
  _Pat('line position', 'rc_line', 'sensors', out: 'num'),
  _Pat('tilt angle (~ °~ )~', 'rc_tilt', 'sensors', out: 'num'),
  _Pat('<AXIS:yaw|pitch|roll> angle (~ °~ )~', 'rc_angle', 'sensors', out: 'num'),
  _Pat(r'$side motor position (~ °~ )~', 'rc_motor_position', 'motors', out: 'num'),
  _Pat(r'$side motor speed (~ %~ )~', 'rc_motor_speed', 'motors', out: 'num'),
  _Pat('servo <PORT:1|2|3|4> angle (~ °~ )~', 'rc_servo_angle', 'motors', out: 'num'),
  _Pat(r'$sensor line sensor (~ %~ )~', 'rc_line_sensor', 'sensors', out: 'num'),
  _Pat('battery <KIND:%=PERCENT|percent=PERCENT|volts=VOLTS>', 'rc_battery', 'sensors', out: 'num'),
  _Pat('temperature (~ °~ C~ )~', 'rc_temperature', 'sensors', out: 'num'),
  _Pat('timer (~ s~ )~', 'rc_timer', 'sensors', out: 'num'),
  _Pat('read analog pin ^PIN', 'rc_read_analog', 'pins', out: 'num'),
  _Pat('read pin ^PIN', 'rc_read_pin', 'pins', out: 'num'),
  _Pat('serial read line', 'rc_serial_read_line', 'pins', out: 'str'),
  _Pat('pick random [FROM] to [TO]', 'math_random_int', 'operators', out: 'num'),
  _Pat('round [NUM]', 'math_round', 'operators', out: 'num', fields: {'OP': 'ROUND'}),
  _Pat('is an~ obstacle closer than [CM] cm~ ?~', 'rc_closer', 'sensors', out: 'bool'),
  _Pat(r'is the~ $sensor sensor on the line ?~', 'rc_on_line', 'sensors', out: 'bool'),
  _Pat(r'is the robot $state ?~', 'rc_is_tilted', 'sensors', out: 'bool'),
  _Pat('is the~ USER button pressed ?~', 'rc_user_pressed', 'sensors', out: 'bool'),
  _Pat('is [X] between [LO] and [HI] ?~', 'rc_between', 'operators', out: 'bool'),
];

// ---------------------------------------------------------------- values

/// A value in a script: a number or text as written, or a block. [type]: num | bool | str | var (a variable,
/// which fits anywhere).
class _Value {
  const _Value.number(num this.number)
      : text = null,
        block = null,
        type = 'num';
  const _Value.text(String this.text)
      : number = null,
        block = null,
        type = 'str';
  const _Value.block(Map<String, dynamic> this.block, this.type)
      : number = null,
        text = null;
  final num? number;
  final String? text;
  final Map<String, dynamic>? block;
  final String type;

  bool fits(String want) => want == 'any' || type == 'var' || type == want;

  /// As a block's input: what was typed goes in the white pill, a block goes over it ([pill]: over a 0).
  Map<String, dynamic> input({bool pill = true}) {
    if (number != null) return {'shadow': _numBlock(number!)};
    if (text != null) return {'shadow': _textBlock(text!)};
    return {if (pill) 'shadow': _numBlock(0), 'block': block};
  }

  /// As a block of its own (for an input that takes no pill).
  Map<String, dynamic> get asBlock => block ?? (number != null ? _numBlock(number!) : _textBlock(text!));
}

Map<String, dynamic> _numBlock(num n) => {
      'type': 'math_number',
      'fields': {'NUM': n}
    };
Map<String, dynamic> _textBlock(String t) => {
      'type': 'text',
      'fields': {'TEXT': t}
    };
Map<String, dynamic> _variable(String type, String name) => {
      'type': type,
      'fields': {
        'VAR': {'name': name}
      }
    };

const _compare = {'<': 'LT', '>': 'GT', '=': 'EQ', '==': 'EQ', '≠': 'NEQ', '!=': 'NEQ', '≤': 'LTE', '<=': 'LTE', '≥': 'GTE', '>=': 'GTE'};
const _addOps = {'+': 'ADD', '-': 'MINUS'};
const _mulOps = {'×': 'MULTIPLY', '*': 'MULTIPLY', '÷': 'DIVIDE', '/': 'DIVIDE'};

/// Reads one line's words. [vars]: the variables a value may name, in lower case.
class _Parser {
  _Parser(this.t, this.vars);
  final List<_Tok> t;
  final Set<String> vars;

  bool _word(int i, String s) => i < t.length && t[i].kind == 'word' && t[i].low == s;
  String? _sym(int i) => i < t.length && t[i].kind == 'sym' ? t[i].text : null;

  // or → and → not → compare → add → multiply → unary → atom
  (_Value, int)? value(int i, String want) {
    final r = want == 'num' ? _add(i) : _or(i);
    return r != null && r.$1.fits(want) ? r : null;
  }

  (_Value, int)? _or(int i) => _logic(i, 'or', 'OR', _and);
  (_Value, int)? _and(int i) => _logic(i, 'and', 'AND', _not);

  (_Value, int)? _logic(int i, String word, String op, (_Value, int)? Function(int) next) {
    var left = next(i);
    while (left != null && _word(left.$2, word)) {
      final right = next(left.$2 + 1);
      if (right == null || !left.$1.fits('bool') || !right.$1.fits('bool')) return left;
      left = (
        _Value.block({
          'type': 'logic_operation',
          'fields': {'OP': op},
          'inputs': {
            'A': {'block': left.$1.asBlock},
            'B': {'block': right.$1.asBlock}
          },
        }, 'bool'),
        right.$2
      );
    }
    return left;
  }

  (_Value, int)? _not(int i) {
    if (!_word(i, 'not')) return _cmp(i);
    final v = _not(i + 1);
    if (v == null || !v.$1.fits('bool')) return null;
    return (
      _Value.block({
        'type': 'logic_negate',
        'inputs': {
          'BOOL': {'block': v.$1.asBlock}
        },
      }, 'bool'),
      v.$2
    );
  }

  (_Value, int)? _cmp(int i) {
    final left = _add(i);
    if (left == null) return null;
    final op = _compare[_sym(left.$2)];
    if (op == null) return left;
    final right = _add(left.$2 + 1);
    if (right == null || left.$1.type == 'bool' || right.$1.type == 'bool') return left;
    return (
      _Value.block({
        'type': 'logic_compare',
        'fields': {'OP': op},
        'inputs': {'A': left.$1.input(), 'B': right.$1.input()},
      }, 'bool'),
      right.$2
    );
  }

  (_Value, int)? _add(int i) => _math(i, _addOps, _mul);
  (_Value, int)? _mul(int i) => _math(i, _mulOps, _unary);

  (_Value, int)? _math(int i, Map<String, String> ops, (_Value, int)? Function(int) next) {
    var left = next(i);
    while (left != null && ops.containsKey(_sym(left.$2))) {
      final right = next(left.$2 + 1);
      if (right == null || !left.$1.fits('num') || !right.$1.fits('num')) return left;
      left = (
        _Value.block({
          'type': 'math_arithmetic',
          'fields': {'OP': ops[_sym(left.$2)]},
          'inputs': {'A': left.$1.input(), 'B': right.$1.input()},
        }, 'num'),
        right.$2
      );
    }
    return left;
  }

  (_Value, int)? _unary(int i) {
    if (_sym(i) != '-') return _atom(i);
    final v = _unary(i + 1);
    if (v == null) return null;
    if (v.$1.number != null) return (_Value.number(-v.$1.number!), v.$2);
    if (!v.$1.fits('num')) return null;
    return (
      _Value.block({
        'type': 'math_arithmetic',
        'fields': {'OP': 'MINUS'},
        'inputs': {'A': const _Value.number(0).input(), 'B': v.$1.input()},
      }, 'num'),
      v.$2
    );
  }

  (_Value, int)? _atom(int i) {
    if (i >= t.length) return null;
    final k = t[i];
    if (k.kind == 'num') return (_Value.number(num.parse(k.text)), i + 1);
    if (k.kind == 'str') return (_Value.text(k.text), i + 1);
    if (k.kind == 'sym') {
      if (k.text != '(') return null;
      final v = _or(i + 1);
      return v != null && _sym(v.$2) == ')' ? (v.$1, v.$2 + 1) : null;
    }
    if (k.low == 'true' || k.low == 'false') {
      return (
        _Value.block({
          'type': 'logic_boolean',
          'fields': {'BOOL': k.low.toUpperCase()}
        }, 'bool'),
        i + 1
      );
    }
    if (k.low == 'join') {
      final a = _unary(i + 1);
      final b = a == null ? null : _unary(a.$2);
      if (a == null || b == null) return null;
      return (
        _Value.block({
          'type': 'text_join',
          'inputs': {'ADD0': a.$1.input(pill: false), 'ADD1': b.$1.input(pill: false)},
        }, 'str'),
        b.$2
      );
    }
    for (final p in _reporters) {
      final m = match(p, i, whole: false);
      if (m != null) return (_Value.block(m.$1, p.out), m.$2);
    }
    // A variable, when the project or this script has one of that name.
    for (var n = 3; n >= 1; n--) {
      if (i + n > t.length || t.sublist(i, i + n).any((x) => x.kind != 'word')) continue;
      final name = t.sublist(i, i + n).map((x) => x.text).join(' ');
      if (vars.contains(name.toLowerCase())) return (_Value.block(_variable('variables_get', name), 'var'), i + n);
    }
    return null;
  }

  /// The block [p] makes when the words from [i] read as it does, and where it ends.
  (Map<String, dynamic>, int)? match(_Pat p, int i, {required bool whole}) {
    final fields = <String, dynamic>{...p.fields};
    final inputs = <String, dynamic>{};
    final end = _walk(p, 0, i, fields, inputs, whole);
    if (end == null) return null;
    return ({'type': p.type, if (fields.isNotEmpty) 'fields': fields, if (inputs.isNotEmpty) 'inputs': inputs}, end);
  }

  int? _walk(_Pat p, int e, int i, Map<String, dynamic> fields, Map<String, dynamic> inputs, bool whole) {
    if (e == p.els.length) return !whole || i == t.length ? i : null;
    final el = p.els[e];
    int? rest(int j) => _walk(p, e + 1, j, fields, inputs, whole);
    switch (el) {
      case _Lit():
        if (i < t.length && t[i].kind != 'str' && el.alts.contains(t[i].low)) {
          final r = rest(i + 1);
          if (r != null) return r;
        }
        return el.optional ? rest(i) : null;
      case _Menu():
        for (final (words, value) in el.options) {
          if (i + words.length > t.length) continue;
          var same = true;
          for (var k = 0; k < words.length && same; k++) {
            same = t[i + k].kind != 'str' && t[i + k].low == words[k];
          }
          if (!same) continue;
          final r = rest(i + words.length);
          if (r != null) {
            fields[el.name] = value;
            return r;
          }
        }
        return null;
      case _Val():
        final v = value(i, el.type);
        if (v == null) return null;
        final r = rest(v.$2);
        if (r == null) return null;
        // A yes / no input has no pill; a number input keeps one under a block; any other shows what was typed.
        inputs[el.name] = el.type == 'bool' ? {'block': v.$1.asBlock} : v.$1.input(pill: el.type == 'num');
        return r;
      case _Num():
        if (i >= t.length || t[i].kind != 'num') return null;
        final r = rest(i + 1);
        if (r != null) fields[el.name] = num.parse(t[i].text);
        return r;
      case _Pin():
        if (i >= t.length || t[i].kind == 'str') return null;
        final m = RegExp(r'^(?:io|gpio|d|pin)?(\d+)$|^a(\d)$').firstMatch(t[i].low);
        if (m == null) return null;
        final r = rest(i + 1);
        if (r != null) fields[el.name] = m.group(1) ?? '${14 + int.parse(m.group(2)!)}';
        return r;
      case _Name():
        // The shortest run of words that lets the rest read.
        for (var j = i + 1; j <= t.length; j++) {
          if (t[j - 1].kind == 'sym') return null;
          final r = rest(j);
          if (r == null) continue;
          final name = t.sublist(i, j).map((x) => x.text).join(' ');
          fields[el.name] = el.name == 'VAR' ? {'name': name} : name;
          return r;
        }
        return null;
    }
  }
}

// ---------------------------------------------------------------- lines → stacks

class _Line {
  _Line(this.text, this.depth);
  final String text;
  final int depth;
  _Pat? pat;
  Map<String, dynamic>? block;
  final body = <_Line>[]; // the blocks inside (for "if": while its condition is true)
  final branches = <(_Line, List<_Line>)>[]; // else if / else, each with its blocks

  void forget() {
    pat = null;
    block = null;
  }
}

final _bullet = RegExp(r'^(?:[-*•]\s+|\d+[.)]\s+)');
final _closing = RegExp(r'^(?:end(?:\s+\w+)?|[{}])$', caseSensitive: false);
final _setsVar = RegExp(r'^(?:set|change) (.+?) (?:to|by) ', caseSensitive: false);
final _varName = RegExp(r'^[A-Za-z_][A-Za-z0-9_ ]*$');

/// Reads a blocks script. [variables]: the names of the project's variables, so a script can use them.
BlockScript parseBlockScript(String script, {Iterable<String> variables = const []}) {
  // The lines, and how deep each sits from its indentation.
  final lines = <_Line>[];
  final indents = <int>[0];
  for (final raw in script.replaceAll('\t', '  ').split('\n')) {
    if (raw.trim().isEmpty) continue;
    final width = raw.length - raw.trimLeft().length;
    var text = raw.trim().replaceFirst(_bullet, '').replaceAll(RegExp(r'\s+'), ' ');
    if (text.endsWith(':')) text = text.substring(0, text.length - 1).trimRight();
    if (text.isEmpty || _closing.hasMatch(text)) continue;
    while (width < indents.last) {
      indents.removeLast();
    }
    if (width > indents.last) indents.add(width);
    lines.add(_Line(text, indents.length - 1));
  }

  // Variables the script itself makes ("set speed to 50"), unless the line is another block ("set LED to red").
  final vars = {for (final v in variables) v.toLowerCase()};
  for (final l in lines) {
    final m = _setsVar.firstMatch(l.text);
    if (m == null || !_varName.hasMatch(m.group(1)!)) continue;
    final probe = _Parser(_tokens(l.text), vars);
    if (_statements.any((p) => p.cat != 'variables' && probe.match(p, 0, whole: true) != null)) continue;
    vars.add(m.group(1)!.toLowerCase());
  }

  for (final l in lines) {
    final parser = _Parser(_tokens(l.text), vars);
    for (final p in _statements) {
      final m = parser.match(p, 0, whole: true);
      if (m == null) continue;
      l.pat = p;
      l.block = m.$1;
      break;
    }
  }

  // What sits inside what.
  var i = 0;
  List<_Line> seq(int depth) {
    final out = <_Line>[];
    while (i < lines.length && lines[i].depth >= depth) {
      final l = lines[i];
      if (l.pat?.kind == RowKind.middle) {
        if (depth > 0) break; // the "if" above takes it
        l.forget(); // an "else" with no "if"
      }
      i++;
      if (l.pat?.kind == RowKind.hat && depth > 0) l.forget(); // "on start" inside another block is not a block
      final kind = l.pat?.kind;
      if (kind == RowKind.hat || kind == RowKind.open) {
        l.body.addAll(seq(l.depth + 1));
        while (l.pat!.type == 'controls_if' && i < lines.length && lines[i].depth == l.depth && lines[i].pat?.kind == RowKind.middle) {
          final branch = lines[i++];
          l.branches.add((branch, seq(l.depth + 1)));
          if (branch.pat!.type == 'else') break;
        }
      }
      out.add(l);
    }
    return out;
  }

  final top = seq(0);

  // "on start" with its blocks written under it but not indented still owns them.
  for (var k = 0; k < top.length; k++) {
    final h = top[k];
    if (h.pat?.kind != RowKind.hat || h.body.isNotEmpty) continue;
    while (k + 1 < top.length && top[k + 1].pat?.kind != RowKind.hat) {
      h.body.add(top.removeAt(k + 1));
    }
  }

  final rows = <BlockRow>[];
  void show(List<_Line> list, int depth) {
    for (final l in list) {
      rows.add(BlockRow(l.text, l.pat?.cat ?? '', depth, l.pat?.kind ?? RowKind.unknown));
      show(l.body, depth + 1);
      for (final (branch, body) in l.branches) {
        rows.add(BlockRow(branch.text, 'control', depth, RowKind.middle));
        show(body, depth + 1);
      }
    }
  }

  show(top, 0);

  // Blockly's JSON. [loose]: what was written after a block nothing can follow.
  final loose = <Map<String, dynamic>>[];
  Map<String, dynamic>? chain(List<_Line> list) {
    Map<String, dynamic>? first, last;
    var cut = false;
    for (final l in list) {
      final b = l.block;
      if (b == null) continue;
      final p = l.pat!;
      final inputs = ((b['inputs'] as Map?) ?? const {}).cast<String, dynamic>();
      if (p.type == 'controls_if') {
        // Its condition was read as IF; Blockly names them IF0, IF1 … with DO0, DO1 … and ELSE.
        final all = <String, dynamic>{'IF0': inputs['IF']};
        final then = chain(l.body);
        if (then != null) all['DO0'] = {'block': then};
        var n = 0, hasElse = false;
        for (final (branch, body) in l.branches) {
          final inner = chain(body);
          if (branch.pat!.type == 'else') {
            hasElse = true;
            if (inner != null) all['ELSE'] = {'block': inner};
          } else {
            n++;
            all['IF$n'] = (branch.block!['inputs'] as Map)['IF'];
            if (inner != null) all['DO$n'] = {'block': inner};
          }
        }
        b['inputs'] = all;
        if (n > 0 || hasElse) b['extraState'] = {if (n > 0) 'elseIfCount': n, if (hasElse) 'hasElse': true};
      } else if (p.kind == RowKind.hat || p.kind == RowKind.open) {
        final inner = chain(l.body);
        if (inner != null) b['inputs'] = {...inputs, 'DO': {'block': inner}};
      }
      if (first == null) {
        first = b;
      } else if (cut) {
        loose.add(b);
      } else {
        last!['next'] = {'block': b};
      }
      last = b;
      cut = p.terminal;
    }
    return first;
  }

  final stacks = <Map<String, dynamic>>[];
  var run = <_Line>[];
  void flush() {
    final s = chain(run);
    if (s != null) stacks.add(s);
    run = [];
  }

  for (final l in top) {
    if (l.pat?.kind == RowKind.hat) {
      flush();
      run = [l];
      flush();
    } else {
      run.add(l);
    }
  }
  flush();
  stacks.addAll(loose);
  return BlockScript(rows, stacks);
}

/// The names of the variables in a project's saved Blockly workspace.
List<String> blocklyVariables(Map<String, dynamic>? workspace) => [
      for (final v in (workspace?['variables'] as List?) ?? const [])
        if (v is Map && v['name'] is String) v['name'] as String
    ];
