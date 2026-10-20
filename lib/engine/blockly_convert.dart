// Turns a project's old block lists ({setup, loop}) into a Blockly workspace (Blockly's JSON
// serialization), so existing projects and the examples open in the Blockly editor, with the
// hardware-first blocks (docs: block catalogue) wherever one means the same thing.
import 'dart:convert';

import 'codegen.dart' show toInt, toNum, varName;

String blocklyFromLists(List<Map<String, dynamic>> setup, List<Map<String, dynamic>> loop) {
  final vars = <String, String>{}; // C++ name → Blockly variable id
  Map<String, dynamic> variable(dynamic name) {
    final n = varName(name);
    return {'id': vars.putIfAbsent(n, () => 'var_$n')};
  }

  Map<String, dynamic> number(num n) => {
        'shadow': {
          'type': 'math_number',
          'fields': {'NUM': n}
        }
      };
  Map<String, dynamic> text(String t) => {
        'shadow': {
          'type': 'text',
          'fields': {'TEXT': t}
        }
      };
  // print “label” joined with a sensor value.
  Map<String, dynamic> printJoin(String label, String reporter) => {
        'type': 'rc_print',
        'inputs': {
          'VALUE': {
            'block': {
              'type': 'text_join',
              'extraState': {'itemCount': 2},
              'inputs': {
                'ADD0': text(label),
                'ADD1': {
                  'block': {'type': reporter}
                },
              },
            }
          }
        },
      };
  String level(dynamic v) => v == 'LOW' ? 'LOW' : 'HIGH';

  Map<String, dynamic>? block(Map<String, dynamic> b) {
    switch (b['t']) {
      case 'led':
        return {
          'type': 'rc_led',
          'fields': {'STATE': level(b['state'])}
        };
      case 'pin':
        return {
          'type': 'rc_pin',
          'fields': {'PIN': '${toInt(b['pin'])}', 'STATE': level(b['state'])}
        };
      case 'tone':
        return {
          'type': 'rc_beep',
          'fields': {'NOTE': '${b['note'] ?? 'C4'}'},
          'inputs': {'SECS': number(toNum(b['secs']))},
        };
      case 'rgb':
        return {
          'type': 'rc_rgb',
          'fields': {'COLOR': '${b['color'] ?? 'red'}'}
        };
      case 'wait':
        return {
          'type': 'rc_wait',
          'fields': {'TIME': toNum(b['secs']), 'UNIT': b['unit'] == 'ms' ? 'ms' : 'secs'}
        };
      case 'button':
        return {
          'type': 'rc_wait_until',
          'inputs': {
            'COND': {
              'block': {'type': 'rc_user_pressed'}
            }
          },
        };
      case 'rand':
        return {
          'type': 'variables_set',
          'fields': {'VAR': variable(b['v'])},
          'inputs': {
            'VALUE': {
              'block': {
                'type': 'math_random_int',
                'inputs': {'FROM': number(toInt(b['a'])), 'TO': number(toInt(b['b']))}
              }
            }
          }
        };
      case 'setvar':
        return {
          'type': 'variables_set',
          'fields': {'VAR': variable(b['v'])},
          'inputs': {'VALUE': number(toInt(b['n']))}
        };
      case 'change':
        return {
          'type': 'math_change',
          'fields': {'VAR': variable(b['v'])},
          'inputs': {'DELTA': number(toInt(b['n']))}
        };
      case 'printvar':
        return {
          'type': 'rc_print',
          'inputs': {
            'VALUE': {
              'block': {
                'type': 'variables_get',
                'fields': {'VAR': variable(b['v'])}
              }
            }
          }
        };
      case 'drive':
        final s = toNum(b['speed']).clamp(0, 100).truncate();
        final (l, r) = switch ('${b['dir'] ?? 'forward'}') {
          'backward' => (-s, -s),
          'left' => (-s, s),
          'right' => (s, -s),
          _ => (s, s),
        };
        return {
          'type': 'rc_drive_lr',
          'inputs': {'L': number(l), 'R': number(r)},
        };
      case 'stop':
        return {'type': 'rc_stop_moving'};
      case 'distance':
        return printJoin('distance_cm=', 'rc_distance');
      case 'linesens':
        return printJoin('line=', 'rc_line');
      case 'serial':
        return {
          'type': 'rc_serial_begin',
          'fields': {'BAUD': b['baud'] == '9600' ? '9600' : '115200'}
        };
      case 'print':
        return {
          'type': 'rc_print',
          'inputs': {'VALUE': text('${b['text'] ?? ''}')},
        };
    }
    return null;
  }

  // A stack, linked through "next" from the last block up.
  Map<String, dynamic>? chain(List<Map<String, dynamic>> list) {
    Map<String, dynamic>? next;
    for (final b in list.reversed) {
      final j = block(b);
      if (j == null) continue;
      if (next != null) j['next'] = {'block': next};
      next = j;
    }
    return next;
  }

  Map<String, dynamic> hat(String type, List<Map<String, dynamic>> list, int y) {
    final body = chain(list);
    return {
      'type': type,
      'x': 24,
      'y': y,
      if (body != null)
        'inputs': {
          'DO': {'block': body}
        },
    };
  }

  final blocks = [hat('rc_on_start', setup, 24), hat('rc_forever', loop, 48 + 56 * (setup.length + 2))];
  return jsonEncode({
    'blocks': {'languageVersion': 0, 'blocks': blocks},
    if (vars.isNotEmpty) 'variables': [for (final e in vars.entries) {'name': e.key, 'id': e.value}],
  });
}
