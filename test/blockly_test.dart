// Blockly support: old block lists → Blockly workspace, and projects that keep a Blockly workspace.
// The Blockly C++ generator itself runs in the browser (web/robocore_editors.js); it was checked
// against genBlocks for every example (same C++ for all 15 example/board pairs).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocore_ide/data/catalog.dart';
import 'package:robocore_ide/engine/blockly_convert.dart';
import 'package:robocore_ide/state/app_state.dart';
import 'package:robocore_ide/state/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state_test.dart' show FakeUsb;

void main() {
  group('blocklyFromLists', () {
    test('setup and loop become on start and forever stacks', () {
      final j = jsonDecode(blocklyFromLists([
        {'t': 'serial', 'baud': '115200'},
        {'t': 'print', 'text': 'hi "there"'},
      ], [
        {'t': 'led', 'state': 'HIGH'},
        {'t': 'wait', 'secs': 0.5, 'unit': 'secs'},
      ])) as Map<String, dynamic>;
      final tops = (j['blocks']['blocks'] as List).cast<Map<String, dynamic>>();
      expect(tops.map((b) => b['type']), ['rc_on_start', 'rc_forever']);
      final first = tops[0]['inputs']['DO']['block'] as Map<String, dynamic>;
      expect(first['type'], 'rc_serial_begin');
      expect(first['next']['block']['type'], 'rc_print');
      expect(first['next']['block']['inputs']['VALUE']['shadow']['fields'], {'TEXT': 'hi "there"'});
      final loop = tops[1]['inputs']['DO']['block'] as Map<String, dynamic>;
      expect(loop['fields'], {'STATE': 'HIGH'});
      expect(loop['next']['block'], {
        'type': 'rc_wait',
        'fields': {'TIME': 0.5, 'UNIT': 'secs'}
      });
      expect(j.containsKey('variables'), isFalse);
    });

    test('variables are declared once and shared by set, change and print', () {
      final j = jsonDecode(blocklyFromLists([], [
        {'t': 'setvar', 'v': 'count', 'n': 0},
        {'t': 'change', 'v': 'count', 'n': 1},
        {'t': 'rand', 'v': 'x', 'a': 0, 'b': 100},
        {'t': 'printvar', 'v': 'count'},
      ])) as Map<String, dynamic>;
      expect(j['variables'], [
        {'name': 'count', 'id': 'var_count'},
        {'name': 'x', 'id': 'var_x'},
      ]);
      final set = j['blocks']['blocks'][1]['inputs']['DO']['block'] as Map<String, dynamic>;
      expect(set['type'], 'variables_set');
      expect(set['fields']['VAR'], {'id': 'var_count'});
      final rand = set['next']['block']['next']['block'] as Map<String, dynamic>;
      expect(rand['inputs']['VALUE']['block']['type'], 'math_random_int');
    });

    test('old blocks become the hardware-first blocks that mean the same', () {
      final j = jsonDecode(blocklyFromLists([], [
        {'t': 'drive', 'dir': 'left', 'speed': 60},
        {'t': 'stop'},
        {'t': 'tone', 'pin': '47', 'note': 'C5', 'secs': 0.2},
        {'t': 'button'},
        {'t': 'distance'},
      ])) as Map<String, dynamic>;
      final blocks = <Map<String, dynamic>>[];
      Map<String, dynamic>? b = j['blocks']['blocks'][1]['inputs']['DO']['block'] as Map<String, dynamic>;
      while (b != null) {
        blocks.add(b);
        b = (b['next'] as Map?)?['block'] as Map<String, dynamic>?;
      }
      expect(blocks.map((x) => x['type']), ['rc_drive_lr', 'rc_stop_moving', 'rc_beep', 'rc_wait_until', 'rc_print']);
      expect(blocks[0]['inputs']['L']['shadow']['fields']['NUM'], -60);
      expect(blocks[0]['inputs']['R']['shadow']['fields']['NUM'], 60);
      expect(blocks[2]['fields'], {'NOTE': 'C5'});
      expect(blocks[2]['inputs']['SECS']['shadow']['fields']['NUM'], 0.2);
      expect(blocks[3]['inputs']['COND']['block']['type'], 'rc_user_pressed');
      final join = blocks[4]['inputs']['VALUE']['block'] as Map<String, dynamic>;
      expect(join['type'], 'text_join');
      expect(join['inputs']['ADD1']['block']['type'], 'rc_distance');
    });

    test('an empty project still has both hats', () {
      final j = jsonDecode(blocklyFromLists([], [])) as Map<String, dynamic>;
      expect((j['blocks']['blocks'] as List).map((b) => b['type']), ['rc_on_start', 'rc_forever']);
      expect((j['blocks']['blocks'] as List).every((b) => !(b as Map).containsKey('inputs')), isTrue);
    });

    test('every example converts without losing a block', () {
      for (final ex in kExamples) {
        final b = ex.blocksFor('v2');
        if (b == null) continue;
        final setup = [for (final x in b['setup'] as List) Map<String, dynamic>.from(x as Map)];
        final loop = [for (final x in b['loop'] as List) Map<String, dynamic>.from(x as Map)];
        final j = jsonDecode(blocklyFromLists(setup, loop)) as Map<String, dynamic>;
        int length(Map<String, dynamic> hat) {
          var n = 0;
          Map<String, dynamic>? x = hat['inputs']?['DO']?['block'] as Map<String, dynamic>?;
          while (x != null) {
            n++;
            x = x['next']?['block'] as Map<String, dynamic>?;
          }
          return n;
        }

        final tops = (j['blocks']['blocks'] as List).cast<Map<String, dynamic>>();
        expect(length(tops[0]), setup.length, reason: ex.id);
        expect(length(tops[1]), loop.length, reason: ex.id);
      }
    });
  });

  group('projects with a Blockly workspace', () {
    test('the workspace and its C++ are saved, and the C++ is what the project generates', () {
      final p = projectFrom(kExamples.firstWhere((e) => e.blocksFor('v2') != null));
      p.blockly = '{"blocks":{}}';
      p.blocklyCode = '// from Blockly\n';
      final back = Project.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(back.blockly, p.blockly);
      expect(back.blocklyCode, p.blocklyCode);
      expect(back.generate(), '// from Blockly\n');
    });

    test('setBlockly updates the main file until it is edited by hand', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(usbLink: FakeUsb());
      await s.load();
      s.openExample(kExamples.firstWhere((e) => e.blocksFor('v2') != null).id);
      final p = s.cur!;
      s.setBlockly('{"a":1}', '// first\n', count: 3);
      expect(p.files.first.content, '// first\n');
      expect(p.blocklyCount, 3);
      s.setBlockly('{"a":2}', '// second\n', count: 4);
      expect(p.files.first.content, '// second\n');
      s.editCode('// by hand\n');
      s.setBlockly('{"a":3}', '// third\n', count: 5);
      expect(p.files.first.content, '// by hand\n');
      expect(p.blocklyCode, '// third\n');
      s.rebuildFromBlocks();
      expect(p.files.first.content, '// third\n');
    });

    test('an edit in the old block editor makes the lists the blocks again', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(usbLink: FakeUsb());
      await s.load();
      s.openExample(kExamples.firstWhere((e) => e.blocksFor('v2') != null).id);
      final p = s.cur!;
      s.setBlockly('{"a":1}', '// blockly\n');
      s.addBlock('stop', stack: 'loop');
      expect(p.blockly, isNull);
      expect(p.generate(), contains('motors.stop();'));
    });
  });
}
