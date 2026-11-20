// Cog's blocks scripts (lib/engine/block_script.dart): the lines the AI writes become rows to draw and Blockly's JSON.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/engine/block_script.dart';

Map<String, dynamic> only(String script, {List<String> variables = const []}) {
  final s = parseBlockScript(script, variables: variables);
  expect(s.unknown, 0, reason: 'every line of "$script" is a block');
  expect(s.stacks, hasLength(1));
  return s.stacks.single;
}

Map<String, dynamic> num0(num n) => {
      'shadow': {
        'type': 'math_number',
        'fields': {'NUM': n}
      }
    };

void main() {
  test('one block, as it reads on the block', () {
    expect(only('move forward for 10 cm'), {
      'type': 'rc_move',
      'fields': {'DIR': 'forward', 'UNIT': 'cm'},
      'inputs': {'AMOUNT': num0(10)},
    });
    expect(only('turn right for 90 °'), {
      'type': 'rc_turn',
      'fields': {'DIR': 'right'},
      'inputs': {'DEG': num0(90)},
    });
    expect(only('turn LED on')['fields'], {'STATE': 'HIGH'});
    expect(only('wait 0.5 secs')['fields'], {'TIME': 0.5, 'UNIT': 'secs'});
    expect(only('play melody power up')['fields'], {'TUNE': 'power up'});
    expect(only('set LED to red'), {
      'type': 'rc_rgb',
      'fields': {'COLOR': 'red'}
    });
    expect(only('stop moving'), {'type': 'rc_stop_moving'});
  });

  test('the way an AI writes them: capitals, spelled-out units, no spaces, a bullet, a colon', () {
    expect(only('Move Forward for 10cm')['type'], 'rc_move');
    expect(only('turn left for 45 degrees')['inputs'], {'DEG': num0(45)});
    expect(only('- wait 2 seconds')['fields'], {'TIME': 2, 'UNIT': 'secs'});
    expect(only('1. set servo 2 to 90')['fields'], {'PORT': '2'});
    expect(only('repeat 4 times:')['type'], 'controls_repeat_ext');
    expect(only('play beep c5 for 0.2 s')['fields'], {'NOTE': 'C5'});
    expect(only('move backwards for 2 rotations')['fields'], {'DIR': 'backward', 'UNIT': 'rotations'});
  });

  test('blocks inside blocks follow the indentation', () {
    final s = parseBlockScript('repeat 4 times\n  move forward for 10 cm\n  turn right for 90 °\nstop moving');
    expect(s.unknown, 0);
    expect([for (final r in s.rows) (r.text, r.cat, r.depth, r.kind)], [
      ('repeat 4 times', 'control', 0, RowKind.open),
      ('move forward for 10 cm', 'movement', 1, RowKind.block),
      ('turn right for 90 °', 'movement', 1, RowKind.block),
      ('stop moving', 'movement', 0, RowKind.block),
    ]);
    final repeat = s.stacks.single;
    expect(repeat['type'], 'controls_repeat_ext');
    expect(repeat['inputs']['TIMES'], num0(4));
    final move = repeat['inputs']['DO']['block'];
    expect(move['type'], 'rc_move');
    expect(move['next']['block']['type'], 'rc_turn');
    expect(move['next']['block']['next'], isNull);
    expect(repeat['next']['block'], {'type': 'rc_stop_moving'});
  });

  test('if, else if and else', () {
    final b = only('if is obstacle closer than 20 cm? then\n'
        '  stop moving\n'
        'else if is USER button pressed? then\n'
        '  turn LED on\n'
        'else\n'
        '  start moving forward');
    expect(b['type'], 'controls_if');
    expect(b['extraState'], {'elseIfCount': 1, 'hasElse': true});
    expect(b['inputs']['IF0']['block'], {
      'type': 'rc_closer',
      'inputs': {'CM': num0(20)},
    });
    expect(b['inputs']['DO0']['block'], {'type': 'rc_stop_moving'});
    expect(b['inputs']['IF1']['block'], {'type': 'rc_user_pressed'});
    expect(b['inputs']['DO1']['block']['type'], 'rc_led');
    expect(b['inputs']['ELSE']['block']['type'], 'rc_start_moving');
    expect(b.containsKey('next'), isFalse);
    final rows = parseBlockScript('if true then\n  stop moving\nelse\n  stop sound').rows;
    expect([for (final r in rows) (r.depth, r.kind)], [(0, RowKind.open), (1, RowKind.block), (0, RowKind.middle), (1, RowKind.block)]);
  });

  test('values: sensors, sums, comparisons, and / or / not', () {
    final cond = only('wait until distance (cm) < 20 and not is USER button pressed?')['inputs']['COND']['block'];
    expect(cond['type'], 'logic_operation');
    expect(cond['fields'], {'OP': 'AND'});
    final less = cond['inputs']['A']['block'];
    expect(less['type'], 'logic_compare');
    expect(less['fields'], {'OP': 'LT'});
    expect(less['inputs']['A']['block'], {'type': 'rc_distance'});
    expect(less['inputs']['B'], num0(20));
    expect(cond['inputs']['B']['block']['type'], 'logic_negate');

    final deg = only('set servo 1 to (distance (cm) * 2 + 10) °')['inputs']['DEG'];
    expect(deg['shadow'], num0(0)['shadow'], reason: 'a number input keeps its pill under the block');
    expect(deg['block']['type'], 'math_arithmetic');
    expect(deg['block']['fields'], {'OP': 'ADD'});
    expect(deg['block']['inputs']['A']['block']['fields'], {'OP': 'MULTIPLY'});
    expect(deg['block']['inputs']['B'], num0(10));

    expect(only('move forward for -5 cm')['inputs']['AMOUNT'], num0(-5));
    expect(only('print "hello"')['inputs']['VALUE'], {
      'shadow': {
        'type': 'text',
        'fields': {'TEXT': 'hello'}
      }
    });
    final join = only('print join "cm: " distance (cm)')['inputs']['VALUE']['block'];
    expect(join['type'], 'text_join');
    expect(join['inputs']['ADD1'], {
      'block': {'type': 'rc_distance'}
    });
    expect(only('if is yaw angle (°) between -10 and 10 ? then')['inputs']['IF0']['block']['type'], 'rc_between');
    expect(only('turn right for pick random 10 to 90 °')['inputs']['DEG']['block']['type'], 'math_random_int');
    expect(only('set pin IO37 to HIGH')['fields'], {'PIN': '37', 'STATE': 'HIGH'});
    expect(only('print read analog pin A0')['inputs']['VALUE']['block']['fields'], {'PIN': '14'});
  });

  test('variables: the script\'s own and the project\'s', () {
    final s = parseBlockScript('set speed to 40\nchange speed by 10\nset movement speed to speed %');
    expect(s.unknown, 0);
    final set = s.stacks.single;
    expect(set['type'], 'variables_set');
    expect(set['fields'], {
      'VAR': {'name': 'speed'}
    });
    final change = set['next']['block'];
    expect(change['type'], 'math_change');
    expect(change['inputs']['DELTA'], num0(10));
    expect(change['next']['block']['inputs']['PCT']['block'], {
      'type': 'variables_get',
      'fields': {
        'VAR': {'name': 'speed'}
      }
    });
    expect(parseBlockScript('move forward for steps cm').unknown, 1, reason: 'no such variable');
    expect(only('move forward for steps cm', variables: ['Steps'])['inputs']['AMOUNT']['block']['type'], 'variables_get');
    expect(only('set LED to red')['type'], 'rc_rgb', reason: 'a block of its own, not a variable called LED');
    expect(
        blocklyVariables({
          'variables': [
            {'name': 'speed', 'id': 'a'},
            {'name': 'count', 'id': 'b'}
          ]
        }),
        ['speed', 'count']);
    expect(blocklyVariables(null), isEmpty);
  });

  test('hats start their own stack, and own the blocks under them even without indentation', () {
    final s = parseBlockScript('on start\n  set movement speed to 40 %\nforever\n  move forward for 10 cm\n  turn right for 90 °');
    expect(s.unknown, 0);
    expect([for (final b in s.stacks) b['type']], ['rc_on_start', 'rc_forever']);
    expect(s.stacks[1]['inputs']['DO']['block']['next']['block']['type'], 'rc_turn');

    final flat = parseBlockScript('on start\nturn LED on\nwait 1 secs\nturn LED off');
    expect(flat.stacks.single['inputs']['DO']['block']['next']['block']['next']['block']['fields'], {'STATE': 'LOW'});
    expect([for (final r in flat.rows) r.depth], [0, 1, 1, 1]);

    final when = only('when obstacle is closer than 15 cm\n  stop moving');
    expect(when['type'], 'rc_when_closer');
    expect(when['inputs']['CM'], num0(15));
    expect(only('when I receive go\n  start moving forward')['fields'], {'MSG': 'go'});
  });

  test('a line that is not a block stays out of the workspace', () {
    final s = parseBlockScript('move forward for 10 cm\nfly to the moon\nturn right for 90 °');
    expect(s.unknown, 1);
    expect(s.rows[1].kind, RowKind.unknown);
    expect(s.rows[1].cat, '');
    final move = s.stacks.single;
    expect(move['next']['block']['type'], 'rc_turn', reason: 'the blocks around it still join');

    for (final wrong in [
      'move forward for fast cm', // not a number
      'turn right for 90 ° quickly', // words left over
      'wait speed secs', // the wait block takes a typed number only
      'if 5 then', // not a yes / no value
      'set servo 9 to 90 °', // no such port
      'else',
      'robot.move(10, CM);',
    ]) {
      final r = parseBlockScript(wrong);
      expect(r.unknown, 1, reason: wrong);
      expect(r.isEmpty, isTrue, reason: wrong);
    }
    expect(parseBlockScript('').rows, isEmpty);
    expect(parseBlockScript('forever\n  on start\n  stop moving').unknown, 1, reason: 'a hat inside a block');
  });

  test('nothing joins on after stop program', () {
    final s = parseBlockScript('stop moving\nstop program\nturn LED on');
    expect(s.unknown, 0);
    expect(s.stacks, hasLength(2));
    expect(s.stacks[0]['next']['block'], {'type': 'rc_stop_program'});
    expect(s.stacks[1]['type'], 'rc_led');
  });

  test('every block in the list Cog is given reads as a block', () {
    // The wording Cog sees: "Blocks and the C++ they make" in server/src/cog.js.
    const lines = [
      'move forward for 10 cm', 'turn right for 90 °', 'start moving forward', 'start moving, steering 30', 'drive left 50 % right 50 %',
      'stop moving', 'set movement speed to 50 %', 'set 1 wheel turn to 18.8 cm', 'run left motor for 1 rotations', 'start left motor at 50 %',
      'stop left motor', 'reset left motor position', 'set servo 1 to 90 °', 'turn LED on', 'turn LED off', 'set LED to red',
      'set LED brightness to 50 %', 'play beep C5 for 0.2 s', 'start playing beep C5', 'play melody success', 'stop sound', 'set yaw angle to 0',
      'reset timer', 'wait 1 secs', 'wait until is USER button pressed?', 'stop program', 'broadcast message1', 'set pin IO37 to HIGH',
      'start serial at 115200 baud', 'print "text"', 'print distance (cm)', 'print serial read line', 'print line position',
      'print tilt angle (°)', 'print yaw angle (°)', 'print left motor position (°)', 'print right motor speed (%)', 'print servo 1 angle (°)',
      'print centre line sensor (%)', 'print battery %', 'print temperature (°C)', 'print timer (s)', 'print distance moved (cm)',
      'print read pin IO3', 'print round 3.6', 'print pick random 1 to 10', 'wait until is centre sensor on the line?',
      'wait until is the robot tilted?', 'wait until is obstacle closer than 20 cm?', 'wait until is 5 between 1 and 10 ?',
    ];
    for (final l in lines) {
      expect(parseBlockScript(l).unknown, 0, reason: l);
    }
  });

  test('the stacks are JSON the editor can take', () {
    const everything = 'on start\n'
        '  set speed to 40\n'
        '  set movement speed to speed %\n'
        '  play melody power up\n'
        'forever\n'
        '  if distance (cm) < 20 and not is USER button pressed? then\n'
        '    stop moving\n'
        '    turn right for pick random 45 to 135 °\n'
        '  else if is the robot tilted? then\n'
        '    set LED to red\n'
        '    play beep C5 for 0.2 s\n'
        '  else\n'
        '    start moving forward\n'
        '  repeat 2 times\n'
        '    set servo 1 to (distance (cm) * 2 + 10) °\n'
        '    wait 0.5 secs\n'
        '  print join "cm: " distance (cm)\n'
        'when I receive go\n'
        '  change speed by 10\n'
        '  broadcast done';
    final s = parseBlockScript(everything);
    expect(s.unknown, 0);
    final again = jsonDecode(jsonEncode(s.stacks)) as List;
    expect([for (final b in again) b['type']], ['rc_on_start', 'rc_forever', 'rc_when_receive']);
    expect(again[1]['inputs']['DO']['block']['extraState'], {'elseIfCount': 1, 'hasElse': true});
    // For a check against the real editor (BLOCK_SCRIPT_DUMP=file flutter test …); not part of the suite.
    final out = Platform.environment['BLOCK_SCRIPT_DUMP'];
    if (out != null) File(out).writeAsStringSync(jsonEncode(s.stacks));
  });
}
