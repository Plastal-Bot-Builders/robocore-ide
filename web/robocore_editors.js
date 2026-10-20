// Blockly and Monaco for the RoboCore IDE, inside robocore_editors.html (#blocks or #code).
//
// The Flutter app (lib/ui/editor/web_editors_web.dart) shows that page in an iframe and calls
// window.rcEditor. Settings and the design come from docs/behaviour-spec.md (Handoff: Blockly,
// Handoff: Monaco) in the RoboCore IDE design.
//
// Blocks: Blockly 13 (web/vendor/blockly), Zelos look, the eight RoboCore categories, and an
// Arduino C++ generator that writes the same code as lib/engine/codegen.dart did for the old blocks.
// Code: Monaco 0.57 (web/vendor/monaco), C++ with Arduino and RoboCore suggestions and hovers,
// compile problems as markers.
'use strict';

(function () {
  const MODE = location.hash === '#code' ? 'code' : 'blocks';

  const INK = '#1B2A41', CREAM = '#F7F1E3', PAPER = '#FFFCF5', YELLOW = '#F2B01E';
  const CATS = {
    output: '#2F6BBF', input: '#7A4FB5', control: YELLOW, math: '#2F7A4C',
    variables: '#B23E7A', robotics: '#B84A26', sensors: '#0F7680', communication: INK,
  };

  // Board context from the app: project name, board id and the pins the pin blocks offer.
  const CTX = { name: 'Sketch', board: 'v2', pins: ['13'], tonePins: ['47'], userPin: 42, theme: 'paper' };

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = () => reject(new Error('Could not load ' + src));
      document.head.appendChild(s);
    });
  }

  function darker(hex, f) {
    const n = parseInt(hex.slice(1), 16);
    const c = [n >> 16, (n >> 8) & 255, n & 255].map((v) => Math.round(v * f));
    return '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
  }

  // ======================================================================= Blocks (Blockly)

  const NOTES = { C4: 262, D4: 294, E4: 330, F4: 349, G4: 392, A4: 440, B4: 494, C5: 523, D5: 587, E5: 659 };
  const COLOURS = {
    red: [255, 0, 0], green: [0, 255, 0], blue: [0, 0, 255], yellow: [255, 200, 0],
    purple: [160, 0, 255], white: [255, 255, 255], off: [0, 0, 0],
  };
  const DRIVE = { forward: [1, 1], backward: [-1, -1], left: [-1, 1], right: [1, -1] };
  const HATS = ['rc_on_start', 'rc_forever'];

  function theme(navy) {
    const styles = {};
    for (const [k, c] of Object.entries(CATS)) {
      const primary = navy && k === 'communication' ? '#3E5A86' : c;
      styles['rc_' + k] = { colourPrimary: primary, colourSecondary: darker(primary, 0.85), colourTertiary: INK };
    }
    // Blockly's own blocks (if, loops, compare, numbers, variables, text) take the RoboCore colours.
    Object.assign(styles, {
      logic_blocks: styles.rc_control, loop_blocks: styles.rc_control, math_blocks: styles.rc_math,
      variable_blocks: styles.rc_variables, variable_dynamic_blocks: styles.rc_variables,
      procedure_blocks: styles.rc_variables, text_blocks: styles.rc_communication,
    });
    const cats = {};
    for (const k of Object.keys(CATS)) cats[k] = { colour: styles['rc_' + k].colourPrimary };
    return Blockly.Theme.defineTheme(navy ? 'robocore-navy' : 'robocore-paper', {
      base: Blockly.Themes.Classic,
      blockStyles: styles,
      categoryStyles: cats,
      componentStyles: {
        workspaceBackgroundColour: navy ? '#17253A' : PAPER,
        toolboxBackgroundColour: navy ? INK : PAPER,
        toolboxForegroundColour: navy ? CREAM : INK,
        flyoutBackgroundColour: navy ? '#22344F' : CREAM,
        flyoutForegroundColour: navy ? CREAM : INK,
        flyoutOpacity: 1,
        scrollbarColour: navy ? CREAM : INK,
        scrollbarOpacity: 0.4,
        insertionMarkerColour: navy ? CREAM : INK,
        insertionMarkerOpacity: 0.3,
        selectedGlowColour: YELLOW,
        cursorColour: YELLOW,
        markerColour: YELLOW,
      },
      fontStyle: { family: 'Barlow, sans-serif', weight: '600', size: 13 },
      startHats: true,
    });
  }

  // Zelos, plus a class on yellow (control) blocks so their labels can be navy instead of cream.
  function registerRenderer() {
    class RcPathObject extends Blockly.zelos.PathObject {
      applyColour(block) {
        super.applyColour(block);
        const primary = (block.style && block.style.colourPrimary || '').toUpperCase();
        this.svgRoot.classList.toggle('rcNavyText', primary === YELLOW);
      }
    }
    class RcRenderer extends Blockly.zelos.Renderer {
      makePathObject(root, style) {
        return new RcPathObject(root, style, this.getConstants());
      }
    }
    Blockly.blockRendering.register('robocore', RcRenderer);
    const css = document.createElement('style');
    css.textContent = [
      '.robocore-renderer .blocklyText { fill: ' + CREAM + '; }',
      '.robocore-renderer .rcNavyText > .blocklyText, .robocore-renderer .rcNavyText > g > .blocklyText { fill: ' + INK + '; }',
      '.robocore-renderer .blocklyEditableText > .blocklyText:not(.blocklyDropdownText) { fill: ' + INK + '; }',
      '.blocklyToolboxCategory, .blocklyTreeRow { border-radius: 6px; margin: 2px 6px; font-weight: 600; }',
      '.blocklyToolboxSelected, .blocklyTreeSelected { background: rgba(242,176,30,.22) !important; box-shadow: inset 3px 0 0 ' + YELLOW + '; }',
      '.blocklyToolboxSelected .blocklyToolboxCategoryLabel, .blocklyTreeSelected .blocklyTreeLabel { color: inherit !important; }',
      '.blocklyToolboxCategoryLabel, .blocklyTreeLabel { font-family: Barlow, sans-serif; font-size: 14px; }',
      '.blocklyWidgetDiv .blocklyMenu, .blocklyDropDownDiv { font-family: Barlow, sans-serif; }',
    ].join('\n');
    document.head.appendChild(css);
  }

  function dropdown(values) {
    return values.map((v) => [v, v]);
  }

  // Pins depend on the board, so these menus are built when they open. The current value always
  // stays in the list so saved projects load whatever the board.
  function pinMenu(tone) {
    return function () {
      const opts = dropdown(tone ? CTX.tonePins : CTX.pins);
      const v = this && typeof this.getValue === 'function' ? this.getValue() : null;
      if (v && !opts.some((o) => o[1] === v)) opts.push([v, v]);
      return opts;
    };
  }

  function defineBlocks() {
    Blockly.common.defineBlocksWithJsonArray([
      // --- Control
      { type: 'rc_on_start', message0: 'on start', message1: '%1', args1: [{ type: 'input_statement', name: 'DO' }],
        style: 'rc_control', tooltip: 'Runs once when the board starts: void setup() { … }' },
      { type: 'rc_forever', message0: 'forever', message1: '%1', args1: [{ type: 'input_statement', name: 'DO' }],
        style: 'rc_control', tooltip: 'Runs again and again: void loop() { … }' },
      { type: 'rc_wait', message0: 'wait %1 %2',
        args0: [{ type: 'field_number', name: 'TIME', value: 1, min: 0 }, { type: 'field_dropdown', name: 'UNIT', options: dropdown(['secs', 'ms']) }],
        previousStatement: null, nextStatement: null, style: 'rc_control', tooltip: 'delay(ms);' },
      // --- Output
      { type: 'rc_led', message0: 'set built-in LED to %1', args0: [{ type: 'field_dropdown', name: 'STATE', options: dropdown(['HIGH', 'LOW']) }],
        previousStatement: null, nextStatement: null, style: 'rc_output', tooltip: 'digitalWrite(LED_BUILTIN, HIGH);' },
      { type: 'rc_rgb', message0: 'set RGB LED to %1', args0: [{ type: 'field_dropdown', name: 'COLOR', options: dropdown(Object.keys(COLOURS)) }],
        previousStatement: null, nextStatement: null, style: 'rc_output', tooltip: 'rgbLedWrite(RGB_BUILTIN, r, g, b);' },
      // --- Input
      { type: 'rc_wait_button', message0: 'wait until USER is pressed',
        previousStatement: null, nextStatement: null, style: 'rc_input', tooltip: 'while (digitalRead(USER_BUTTON) == HIGH) { delay(10); }' },
      { type: 'rc_user_pressed', message0: 'USER pressed?', output: 'Boolean', style: 'rc_input',
        tooltip: 'digitalRead(USER_BUTTON) == LOW' },
      // --- Robotics
      { type: 'rc_drive', message0: 'drive %1 at %2 %%',
        args0: [{ type: 'field_dropdown', name: 'DIR', options: dropdown(Object.keys(DRIVE)) }, { type: 'field_number', name: 'SPEED', value: 60, min: 0, max: 100, precision: 1 }],
        previousStatement: null, nextStatement: null, style: 'rc_robotics', tooltip: 'motors.drive(left, right);' },
      { type: 'rc_stop', message0: 'stop motors', previousStatement: null, nextStatement: null, style: 'rc_robotics', tooltip: 'motors.stop();' },
      // --- Sensors
      { type: 'rc_distance', message0: 'distance (cm)', output: 'Number', style: 'rc_sensors', tooltip: 'sonar.distanceCm()' },
      { type: 'rc_line', message0: 'line position', output: 'Number', style: 'rc_sensors',
        tooltip: 'line.read(): -1 (line on the left) to 1 (on the right)' },
      { type: 'rc_print_distance', message0: 'print distance in cm', previousStatement: null, nextStatement: null,
        style: 'rc_sensors', tooltip: 'Serial.println(sonar.distanceCm(), 1);' },
      { type: 'rc_print_line', message0: 'print line sensor', previousStatement: null, nextStatement: null,
        style: 'rc_sensors', tooltip: 'Serial.println(line.read(), 2);' },
      // --- Communication
      { type: 'rc_serial_begin', message0: 'start serial at %1 baud', args0: [{ type: 'field_dropdown', name: 'BAUD', options: dropdown(['115200', '9600']) }],
        previousStatement: null, nextStatement: null, style: 'rc_communication', tooltip: 'Serial.begin(115200);' },
      { type: 'rc_print_text', message0: 'print %1', args0: [{ type: 'field_input', name: 'TEXT', text: 'Hello' }],
        previousStatement: null, nextStatement: null, style: 'rc_communication', tooltip: 'Serial.println("…");' },
      { type: 'rc_print', message0: 'print value %1', args0: [{ type: 'input_value', name: 'VALUE' }],
        previousStatement: null, nextStatement: null, style: 'rc_communication', tooltip: 'Serial.println(value);' },
    ]);
    // Blocks whose pin menus depend on the board.
    Blockly.Blocks.rc_pin = {
      init() {
        this.appendDummyInput().appendField('set pin').appendField(new Blockly.FieldDropdown(pinMenu(false)), 'PIN')
          .appendField('to').appendField(new Blockly.FieldDropdown(dropdown(['HIGH', 'LOW'])), 'STATE');
        this.setPreviousStatement(true); this.setNextStatement(true); this.setStyle('rc_output');
        this.setTooltip('digitalWrite(pin, HIGH);');
      },
    };
    Blockly.Blocks.rc_tone = {
      init() {
        this.appendDummyInput().appendField('tone pin').appendField(new Blockly.FieldDropdown(pinMenu(true)), 'PIN')
          .appendField(new Blockly.FieldDropdown(dropdown(Object.keys(NOTES))), 'NOTE')
          .appendField('for').appendField(new Blockly.FieldNumber(0.5, 0), 'SECS').appendField('s');
        this.setPreviousStatement(true); this.setNextStatement(true); this.setStyle('rc_output');
        this.setTooltip('tone(pin, frequency, ms); delay(ms);');
      },
    };
    // Comparisons sit with Math.
    const compareInit = Blockly.Blocks.logic_compare.init;
    Blockly.Blocks.logic_compare.init = function () { compareInit.call(this); this.setStyle('math_blocks'); };
  }

  const num = (v) => ({ shadow: { type: 'math_number', fields: { NUM: v } } });
  const TOOLBOX = {
    kind: 'categoryToolbox',
    contents: [
      { kind: 'category', name: 'Output', categorystyle: 'output', contents: [
        { kind: 'block', type: 'rc_led' }, { kind: 'block', type: 'rc_rgb' }, { kind: 'block', type: 'rc_pin' }, { kind: 'block', type: 'rc_tone' }] },
      { kind: 'category', name: 'Input', categorystyle: 'input', contents: [
        { kind: 'block', type: 'rc_wait_button' }, { kind: 'block', type: 'rc_user_pressed' }] },
      { kind: 'category', name: 'Control', categorystyle: 'control', contents: [
        { kind: 'block', type: 'rc_on_start' }, { kind: 'block', type: 'rc_forever' }, { kind: 'block', type: 'rc_wait' },
        { kind: 'block', type: 'controls_if' },
        { kind: 'block', type: 'controls_if', extraState: { hasElse: true } },
        { kind: 'block', type: 'controls_repeat_ext', inputs: { TIMES: num(10) } },
        { kind: 'block', type: 'controls_whileUntil' },
        { kind: 'block', type: 'logic_operation' }, { kind: 'block', type: 'logic_negate' }, { kind: 'block', type: 'logic_boolean' }] },
      { kind: 'category', name: 'Math', categorystyle: 'math', contents: [
        { kind: 'block', type: 'math_number' },
        { kind: 'block', type: 'logic_compare', inputs: { A: num(0), B: num(20) }, fields: { OP: 'LT' } },
        { kind: 'block', type: 'math_arithmetic', inputs: { A: num(1), B: num(1) } },
        { kind: 'block', type: 'math_random_int', inputs: { FROM: num(0), TO: num(100) } }] },
      { kind: 'category', name: 'Variables', categorystyle: 'variables', custom: 'VARIABLE' },
      { kind: 'category', name: 'Robotics', categorystyle: 'robotics', contents: [
        { kind: 'block', type: 'rc_drive' }, { kind: 'block', type: 'rc_stop' }] },
      { kind: 'category', name: 'Sensors', categorystyle: 'sensors', contents: [
        { kind: 'block', type: 'rc_distance' }, { kind: 'block', type: 'rc_line' },
        { kind: 'block', type: 'rc_print_distance' }, { kind: 'block', type: 'rc_print_line' }] },
      { kind: 'category', name: 'Communication', categorystyle: 'communication', contents: [
        { kind: 'block', type: 'rc_serial_begin' }, { kind: 'block', type: 'rc_print_text' },
        { kind: 'block', type: 'rc_print', inputs: { VALUE: num(0) } }, { kind: 'block', type: 'text' }] },
    ],
  };

  // ---------------------------------------------------------------- Arduino C++ generator

  const O = { ATOMIC: 0, POSTFIX: 2, PREFIX: 3, MULT: 5, ADD: 6, REL: 8, EQ: 9, AND: 13, OR: 14, NONE: 99 };
  let cpp = null;

  const toNum = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
  const toInt = (v) => Math.trunc(toNum(v));
  const cstr = (s) => String(s == null ? '' : s).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const fmt = (n) => (Number.isInteger(n) ? String(n) : String(+n.toFixed(6)));

  function makeGenerator() {
    const g = new Blockly.CodeGenerator('ArduinoCpp');
    g.INDENT = '  ';
    g.addReservedWords('setup,loop,motors,sonar,line,Serial,int,float,long,bool,char,byte,if,else,for,while,do,return,' +
      'break,continue,true,false,HIGH,LOW,INPUT,OUTPUT,delay,random,tone,digitalWrite,digitalRead,analogRead');
    g.init = function (ws) {
      Object.getPrototypeOf(g).init.call(this, ws);
      if (!this.nameDB_) this.nameDB_ = new Blockly.Names(this.RESERVED_WORDS_);
      else this.nameDB_.reset();
      this.nameDB_.setVariableMap(ws.getVariableMap());
      this.nameDB_.populateVariables(ws);
    };
    g.finish = (code) => code;
    g.scrubNakedValue = (line) => line + ';\n';
    g.scrub_ = function (block, code, thisOnly) {
      const next = block.nextConnection && block.nextConnection.targetBlock();
      return thisOnly || !next ? code : code + this.blockToCode(next);
    };
    const varName = (block) => g.nameDB_.getName(block.getFieldValue('VAR'), Blockly.Names.NameType.VARIABLE);
    const f = g.forBlock;

    // Hats only frame setup() / loop(); their bodies are generated by generate().
    f.rc_on_start = () => '';
    f.rc_forever = () => '';
    f.rc_wait = (b) => {
      const ms = Math.round(toNum(b.getFieldValue('TIME')) * (b.getFieldValue('UNIT') === 'ms' ? 1 : 1000));
      return 'delay(' + Math.max(0, ms) + ');\n';
    };
    f.rc_led = (b) => 'digitalWrite(LED_BUILTIN, ' + (b.getFieldValue('STATE') === 'LOW' ? 'LOW' : 'HIGH') + ');\n';
    f.rc_pin = (b) => 'digitalWrite(' + toInt(b.getFieldValue('PIN')) + ', ' + (b.getFieldValue('STATE') === 'LOW' ? 'LOW' : 'HIGH') + ');\n';
    f.rc_rgb = (b) => {
      const name = b.getFieldValue('COLOR'), c = COLOURS[name] || COLOURS.off;
      return 'rgbLedWrite(RGB_BUILTIN, ' + c.join(', ') + ');  // ' + name + '\n';
    };
    f.rc_tone = (b) => {
      const ms = Math.max(0, Math.round(toNum(b.getFieldValue('SECS')) * 1000)), note = b.getFieldValue('NOTE');
      return 'tone(' + toInt(b.getFieldValue('PIN')) + ', ' + (NOTES[note] || 262) + ', ' + ms + ');  // ' + note + '\ndelay(' + ms + ');\n';
    };
    f.rc_wait_button = () => 'while (digitalRead(USER_BUTTON) == HIGH) {\n  delay(10);\n}\n';
    f.rc_user_pressed = () => ['digitalRead(USER_BUTTON) == LOW', O.EQ];
    f.rc_drive = (b) => {
      const s = Math.trunc(Math.min(100, Math.max(0, toNum(b.getFieldValue('SPEED'))))), m = DRIVE[b.getFieldValue('DIR')] || DRIVE.forward;
      return 'motors.drive(' + m[0] * s + ', ' + m[1] * s + ');\n';
    };
    f.rc_stop = () => 'motors.stop();\n';
    f.rc_distance = () => ['sonar.distanceCm()', O.POSTFIX];
    f.rc_line = () => ['line.read()', O.POSTFIX];
    f.rc_print_distance = () => 'Serial.print("distance_cm=");\nSerial.println(sonar.distanceCm(), 1);\n';
    f.rc_print_line = () => 'Serial.print("line=");\nSerial.println(line.read(), 2);\n';
    f.rc_serial_begin = (b) => 'Serial.begin(' + (b.getFieldValue('BAUD') === '9600' ? 9600 : 115200) + ');\n';
    f.rc_print_text = (b) => 'Serial.println("' + cstr(b.getFieldValue('TEXT')) + '");\n';
    f.rc_print = (b) => 'Serial.println(' + (g.valueToCode(b, 'VALUE', O.NONE) || '0') + ');\n';

    // Blockly's own blocks in C++.
    f.controls_if = (b) => {
      let code = '', n = 0;
      do {
        const cond = g.valueToCode(b, 'IF' + n, O.NONE) || 'false';
        code += (n ? ' else if (' : 'if (') + cond + ') {\n' + g.statementToCode(b, 'DO' + n) + '}';
        n++;
      } while (b.getInput('IF' + n));
      if (b.getInput('ELSE')) code += ' else {\n' + g.statementToCode(b, 'ELSE') + '}';
      return code + '\n';
    };
    f.controls_repeat_ext = (b) => {
      const times = g.valueToCode(b, 'TIMES', O.REL) || '0';
      const i = g.nameDB_.getDistinctName('i', Blockly.Names.NameType.VARIABLE);
      return 'for (int ' + i + ' = 0; ' + i + ' < ' + times + '; ' + i + '++) {\n' + g.statementToCode(b, 'DO') + '}\n';
    };
    f.controls_whileUntil = (b) => {
      const until = b.getFieldValue('MODE') === 'UNTIL';
      let cond = g.valueToCode(b, 'BOOL', until ? O.PREFIX : O.NONE) || 'false';
      if (until) cond = '!' + cond;
      return 'while (' + cond + ') {\n' + g.statementToCode(b, 'DO') + '}\n';
    };
    f.logic_compare = (b) => {
      const op = { EQ: '==', NEQ: '!=', LT: '<', LTE: '<=', GT: '>', GTE: '>=' }[b.getFieldValue('OP')];
      const order = op === '==' || op === '!=' ? O.EQ : O.REL;
      return [(g.valueToCode(b, 'A', order) || '0') + ' ' + op + ' ' + (g.valueToCode(b, 'B', order) || '0'), order];
    };
    f.logic_operation = (b) => {
      const and = b.getFieldValue('OP') === 'AND', order = and ? O.AND : O.OR;
      return [(g.valueToCode(b, 'A', order) || 'false') + (and ? ' && ' : ' || ') + (g.valueToCode(b, 'B', order) || 'false'), order];
    };
    f.logic_negate = (b) => ['!' + (g.valueToCode(b, 'BOOL', O.PREFIX) || 'true'), O.PREFIX];
    f.logic_boolean = (b) => [b.getFieldValue('BOOL') === 'TRUE' ? 'true' : 'false', O.ATOMIC];
    f.math_number = (b) => {
      const n = toNum(b.getFieldValue('NUM'));
      return [fmt(n), n < 0 ? O.PREFIX : O.ATOMIC];
    };
    f.math_arithmetic = (b) => {
      const op = b.getFieldValue('OP');
      if (op === 'POWER') return ['pow(' + (g.valueToCode(b, 'A', O.NONE) || '0') + ', ' + (g.valueToCode(b, 'B', O.NONE) || '0') + ')', O.POSTFIX];
      const [sym, order] = { ADD: [' + ', O.ADD], MINUS: [' - ', O.ADD], MULTIPLY: [' * ', O.MULT], DIVIDE: [' / ', O.MULT] }[op];
      return [(g.valueToCode(b, 'A', order) || '0') + sym + (g.valueToCode(b, 'B', order + 0.5) || '0'), order];
    };
    // random(a, b + 1) like the old "random" block; a literal top bound is added up front.
    f.math_random_int = (b) => {
      const from = g.valueToCode(b, 'FROM', O.NONE) || '0', to = g.valueToCode(b, 'TO', O.ADD) || '0';
      const top = /^-?\d+$/.test(to) ? String(parseInt(to, 10) + 1) : to + ' + 1';
      return ['random(' + from + ', ' + top + ')', O.POSTFIX];
    };
    f.variables_get = (b) => [varName(b), O.ATOMIC];
    f.variables_set = (b) => varName(b) + ' = ' + (g.valueToCode(b, 'VALUE', O.NONE) || '0') + ';\n';
    f.math_change = (b) => varName(b) + ' += ' + (g.valueToCode(b, 'DELTA', O.NONE) || '0') + ';\n';
    f.text = (b) => ['"' + cstr(b.getFieldValue('TEXT')) + '"', O.ATOMIC];
    return g;
  }

  function live(b) {
    return b.isEnabled() && !(typeof b.getInheritedDisabled === 'function' && b.getInheritedDisabled());
  }

  // The whole sketch, laid out like lib/engine/codegen.dart (includes, globals, setup, loop).
  function generate(ws) {
    cpp.init(ws);
    const hats = ws.getTopBlocks(true).filter((b) => HATS.includes(b.type) && live(b));
    const used = new Set(), pins = [], tonePins = [], vars = [];
    const add = (list, v) => { if (!list.includes(v)) list.push(v); };
    for (const hat of hats) {
      for (const b of hat.getDescendants(true)) {
        if (!live(b)) continue;
        used.add(b.type);
        if (b.type === 'rc_pin') add(pins, String(toInt(b.getFieldValue('PIN'))));
        if (b.type === 'rc_tone') add(tonePins, String(toInt(b.getFieldValue('PIN'))));
        if (['variables_set', 'variables_get', 'math_change'].includes(b.type)) {
          add(vars, cpp.nameDB_.getName(b.getFieldValue('VAR'), Blockly.Names.NameType.VARIABLE));
        }
      }
    }
    const has = (...t) => t.some((x) => used.has(x));
    const v2 = CTX.board === 'v2';
    const usesMot = has('rc_drive', 'rc_stop'), usesSonar = has('rc_distance', 'rc_print_distance'),
      usesLine = has('rc_line', 'rc_print_line'), usesBtn = has('rc_wait_button', 'rc_user_pressed');
    const needSerial = has('rc_print_text', 'rc_print', 'rc_print_distance', 'rc_print_line') && !has('rc_serial_begin');

    const body = (type) => hats.filter((h) => h.type === type).map((h) => cpp.statementToCode(h, 'DO')).join('');
    const setupBody = body('rc_on_start'), loopBody = body('rc_forever');

    const l = ['// ' + CTX.name, '// Made with blocks in RoboCore IDE.', ''];
    if (usesMot) l.push('#include <RoboCoreMotors.h>');
    if (usesSonar || usesLine) l.push('#include <RoboCoreSensors.h>');
    if (usesBtn) l.push(v2 ? '#define USER_BUTTON ' + CTX.userPin : '#define USER_BUTTON 0');
    const glob = [];
    if (usesMot) glob.push('RoboCoreMotors motors;');
    if (usesSonar) glob.push('Sonar sonar;');
    if (usesLine) glob.push('LineSensor line;');
    for (const v of vars) glob.push('int ' + v + ' = 0;');
    if (l.length > 3) l.push('');
    if (glob.length) l.push(...glob, '');

    const setup = [];
    if (needSerial) setup.push('Serial.begin(115200);');
    if (has('rc_led')) setup.push('pinMode(LED_BUILTIN, OUTPUT);');
    for (const p of pins) setup.push('pinMode(' + p + ', OUTPUT);');
    for (const p of tonePins) if (!pins.includes(p)) setup.push('pinMode(' + p + ', OUTPUT);');
    if (usesBtn) setup.push(v2 ? 'pinMode(USER_BUTTON, INPUT);' : 'pinMode(USER_BUTTON, INPUT_PULLUP);');
    if (usesMot) setup.push('motors.begin();');
    if (usesSonar) setup.push('sonar.begin();');
    if (usesLine) setup.push('line.begin();');
    const lines = (code) => (code ? code.replace(/\n$/, '').split('\n') : []);
    l.push('void setup() {', ...setup.map((s) => '  ' + s), ...lines(setupBody), '}', '', 'void loop() {', ...lines(loopBody), '}', '');
    return l.join('\n');
  }

  let ws = null, onBlocksChange = null, loading = false, timer = 0;

  // Blocks a student placed: not the two hats or the number fields inside other blocks.
  const countBlocks = (w) => w.getAllBlocks(false).filter((b) => !b.isShadow() && !HATS.includes(b.type)).length;

  function emitBlocks() {
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (!ws || !onBlocksChange) return;
      const json = JSON.stringify(Blockly.serialization.workspaces.save(ws));
      onBlocksChange(json, generate(ws), countBlocks(ws));
    }, 60);
  }

  function blocksOptions(o) {
    if (o.name != null) CTX.name = o.name;
    if (o.board) CTX.board = o.board;
    if (o.pins) CTX.pins = o.pins;
    if (o.tonePins) CTX.tonePins = o.tonePins;
    if (o.userPin != null) CTX.userPin = o.userPin;
  }

  function loadWorkspace(json, tidy) {
    loading = true;
    Blockly.Events.disable();
    try {
      ws.clear();
      if (json) Blockly.serialization.workspaces.load(JSON.parse(json), ws);
      if (tidy) ws.cleanUp();
    } catch (e) {
      console.error('RoboCore: could not load the blocks', e);
    } finally {
      Blockly.Events.enable();
      loading = false;
    }
    ws.clearUndo();
    ws.scrollCenter();
    emitBlocks();
  }

  const blocksApi = {
    async mount(optionsJson, json, tidy, onChange) {
      await ready;
      const o = JSON.parse(optionsJson);
      blocksOptions(o);
      onBlocksChange = onChange;
      setTheme(o.theme);
      ws = Blockly.inject(document.getElementById('host'), {
        toolbox: TOOLBOX,
        renderer: 'robocore',
        theme: CTX.theme === 'navy' ? NAVY : PAPER_THEME,
        media: 'vendor/blockly/media/',
        grid: { spacing: 24, length: 1, colour: 'rgba(27,42,65,.4)', snap: true },
        zoom: { controls: true, wheel: false, pinch: true, startScale: 0.9, minScale: 0.5, maxScale: 2 },
        move: { scrollbars: true, drag: true, wheel: true },
        trashcan: true,
        maxTrashcanContents: 32,
        sounds: false,
      });
      // The app hides this frame while the C++ tab is open; re-measure when it shows again.
      new ResizeObserver(() => { if (ws) Blockly.svgResize(ws); }).observe(document.getElementById('host'));
      ws.addChangeListener(Blockly.Events.disableOrphans);
      ws.addChangeListener((e) => {
        if (loading || e.isUiEvent) return;
        emitBlocks();
      });
      loadWorkspace(json, tidy);
    },
    load(json, tidy) { if (ws) loadWorkspace(json, tidy); },
    setOptions(optionsJson) {
      const o = JSON.parse(optionsJson);
      const nameOrBoard = (o.name != null && o.name !== CTX.name) || (o.board && o.board !== CTX.board);
      blocksOptions(o);
      if (o.theme && o.theme !== CTX.theme) { setTheme(o.theme); if (ws) ws.setTheme(CTX.theme === 'navy' ? NAVY : PAPER_THEME); }
      if (nameOrBoard) emitBlocks();
    },
    undo() { if (ws) ws.undo(false); },
    redo() { if (ws) ws.undo(true); },
    clear() { if (ws) { Blockly.Events.setGroup(true); ws.clear(); Blockly.Events.setGroup(false); } },
    count() { return ws ? countBlocks(ws) : 0; },
  };

  let PAPER_THEME = null, NAVY = null;
  function setTheme(t) {
    CTX.theme = t === 'navy' ? 'navy' : 'paper';
    document.documentElement.style.setProperty('--rc-bg', CTX.theme === 'navy' ? '#17253A' : PAPER);
  }

  // ======================================================================= Code (Monaco)

  let editor = null, models = {}, onCodeChange = null, onCursor = null, applying = false, words = [];

  function defineMonacoThemes() {
    const rules = (navy) => {
      const ink = navy ? 'F7F1E3' : '1B2A41', warm = navy ? 'E8B04B' : '8A5A00', soft = navy ? 'ACADAC' : '68717E';
      return [
        { token: '', foreground: ink },
        { token: 'keyword', foreground: ink, fontStyle: 'bold' },
        { token: 'type', foreground: ink, fontStyle: 'bold' },
        { token: 'number', foreground: warm },
        { token: 'string', foreground: warm },
        { token: 'comment', foreground: soft, fontStyle: 'italic' },
        { token: 'keyword.directive', foreground: ink, fontStyle: 'bold' },
        { token: 'delimiter', foreground: ink },
      ];
    };
    const common = {
      'editorSuggestWidget.background': '#FFFFFF', 'editorSuggestWidget.border': '#1B2A4129',
      'editorSuggestWidget.selectedBackground': '#F2B01E38', 'editorHoverWidget.background': '#FFFFFF',
      'editorHoverWidget.border': '#1B2A4129', 'diffEditor.insertedTextBackground': '#F2B01E38',
      'diffEditor.removedTextBackground': '#1B2A410F', focusBorder: YELLOW,
      'editor.lineHighlightBackground': '#F2B01E1F', 'editor.selectionBackground': '#F2B01E55',
      'editorOverviewRuler.errorForeground': '#1B2A41', 'editorOverviewRuler.warningForeground': '#8A5A00',
      'editorBracketMatch.border': '#F2B01E', 'editorBracketMatch.background': '#F2B01E33',
    };
    monaco.editor.defineTheme('robocore-paper', {
      base: 'vs', inherit: true, rules: rules(false),
      colors: Object.assign({}, common, {
        'editor.background': PAPER, 'editor.foreground': INK, 'editorLineNumber.foreground': '#1B2A4166',
        'editorLineNumber.activeForeground': INK, 'editorError.foreground': INK, 'editorWarning.foreground': '#8A5A00',
        'editorCursor.foreground': INK,
      }),
    });
    monaco.editor.defineTheme('robocore-navy', {
      base: 'vs-dark', inherit: true, rules: rules(true),
      colors: Object.assign({}, common, {
        'editor.background': INK, 'editor.foreground': CREAM, 'editorLineNumber.foreground': '#F7F1E366',
        'editorLineNumber.activeForeground': CREAM, 'editorError.foreground': CREAM, 'editorWarning.foreground': '#E8B04B',
        'editorCursor.foreground': CREAM, 'editorSuggestWidget.background': '#22344F', 'editorHoverWidget.background': '#22344F',
        'editorSuggestWidget.foreground': CREAM, 'editorHoverWidget.foreground': CREAM,
      }),
    });
  }

  // Suggestions and hovers from the app's Arduino + RoboCore word list ([name, '(params)']).
  function registerProviders() {
    monaco.languages.registerCompletionItemProvider('cpp', {
      triggerCharacters: ['.'],
      provideCompletionItems(model, pos) {
        const line = model.getLineContent(pos.lineNumber).slice(0, pos.column - 1);
        const m = /[A-Za-z_][\w.]*$/.exec(line);
        const typed = m ? m[0] : '';
        const range = new monaco.Range(pos.lineNumber, pos.column - typed.length, pos.lineNumber, pos.column);
        return {
          suggestions: words.map(([w, params]) => ({
            label: w,
            kind: params ? monaco.languages.CompletionItemKind.Function : monaco.languages.CompletionItemKind.Constant,
            detail: w + (params || ''),
            insertText: params ? w + '($0)' : w,
            insertTextRules: params ? monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet : undefined,
            range,
          })),
        };
      },
    });
    monaco.languages.registerHoverProvider('cpp', {
      provideHover(model, pos) {
        const line = model.getLineContent(pos.lineNumber);
        const re = /[A-Za-z_][\w.]*/g;
        let m;
        while ((m = re.exec(line))) {
          if (pos.column - 1 >= m.index && pos.column - 1 <= m.index + m[0].length) {
            const hit = words.find(([w]) => w === m[0]) || words.find(([w]) => w.endsWith('.' + m[0]));
            if (!hit) return null;
            return {
              range: new monaco.Range(pos.lineNumber, m.index + 1, pos.lineNumber, m.index + m[0].length + 1),
              contents: [{ value: '```cpp\n' + hit[0] + (hit[1] || '') + '\n```' }],
            };
          }
        }
        return null;
      },
    });
  }

  function codeOptions(o) {
    const opts = {};
    if (o.fontSize) opts.fontSize = o.fontSize;
    if (o.wrap != null) opts.wordWrap = o.wrap ? 'on' : 'off';
    if (o.autocomplete != null) opts.quickSuggestions = o.autocomplete;
    if (o.words) words = o.words;
    if (o.theme) { setTheme(o.theme); monaco.editor.setTheme(CTX.theme === 'navy' ? 'robocore-navy' : 'robocore-paper'); }
    return opts;
  }

  const codeApi = {
    async mount(optionsJson, onChange, onCursorMove) {
      await ready;
      onCodeChange = onChange;
      onCursor = onCursorMove;
      const o = JSON.parse(optionsJson);
      const opts = codeOptions(o);
      editor = monaco.editor.create(document.getElementById('host'), Object.assign({
        language: 'cpp',
        theme: CTX.theme === 'navy' ? 'robocore-navy' : 'robocore-paper',
        automaticLayout: true,
        minimap: { enabled: false },
        fontFamily: "'JetBrains Mono', ui-monospace, monospace",
        fontSize: 13,
        lineHeight: 20,
        tabSize: 2,
        insertSpaces: true,
        glyphMargin: true,
        folding: true,
        showFoldingControls: 'mouseover',
        stickyScroll: { enabled: false },
        parameterHints: { enabled: true },
        lightbulb: { enabled: 'on' },
        renderLineHighlight: 'all',
        bracketPairColorization: { enabled: false },
        guides: { bracketPairs: false, indentation: true },
        scrollBeyondLastLine: false,
        fixedOverflowWidgets: true,
        padding: { top: 8 },
      }, opts));
      editor.onDidChangeModelContent(() => {
        if (applying || !onCodeChange) return;
        const model = editor.getModel();
        const key = Object.keys(models).find((k) => models[k] === model);
        onCodeChange(key || '', model.getValue());
      });
      editor.onDidChangeCursorPosition((e) => {
        if (onCursor) onCursor(e.position.lineNumber, e.position.column);
      });
    },
    // Shows file `key` with `text`. Text that differs from the editor's (blocks regenerated it,
    // or another file was opened) replaces the model's content.
    setFile(key, text, readOnly) {
      if (!editor) return;
      let model = models[key];
      if (!model) {
        model = monaco.editor.createModel(text, 'cpp', monaco.Uri.parse('file:///' + encodeURI(key)));
        models[key] = model;
      } else if (model.getValue() !== text) {
        applying = true;
        model.pushEditOperations([], [{ range: model.getFullModelRange(), text }], () => null);
        applying = false;
      }
      if (editor.getModel() !== model) editor.setModel(model);
      editor.updateOptions({ readOnly: !!readOnly, domReadOnly: !!readOnly });
    },
    setOptions(optionsJson) { if (editor) editor.updateOptions(codeOptions(JSON.parse(optionsJson))); },
    // problems: [{line, column, message, severity}] for the file on screen.
    setMarkers(key, problemsJson) {
      const model = models[key];
      if (!model) return;
      const sev = { error: monaco.MarkerSeverity.Error, warning: monaco.MarkerSeverity.Warning };
      const markers = JSON.parse(problemsJson).filter((p) => p.line >= 1 && p.line <= model.getLineCount()).map((p) => {
        const col = Math.max(1, p.column || 1);
        const word = p.column ? model.getWordAtPosition({ lineNumber: p.line, column: col }) : null;
        return {
          severity: sev[p.severity] || monaco.MarkerSeverity.Info,
          message: p.message,
          startLineNumber: p.line,
          startColumn: word ? word.startColumn : (p.column ? col : model.getLineFirstNonWhitespaceColumn(p.line) || 1),
          endLineNumber: p.line,
          endColumn: word ? word.endColumn : model.getLineMaxColumn(p.line),
        };
      });
      monaco.editor.setModelMarkers(model, 'arduino-cli', markers);
    },
    reveal(line, column) {
      if (!editor) return;
      editor.revealLineInCenter(line);
      editor.setPosition({ lineNumber: line, column: Math.max(1, column || 1) });
      editor.focus();
    },
    find() { if (editor) { editor.focus(); editor.getAction('actions.find').run(); } },
    focus() { if (editor) editor.focus(); },
  };

  // ======================================================================= start-up

  const ready = (async () => {
    if (MODE === 'blocks') {
      await loadScript('vendor/blockly/blockly_compressed.js');
      await loadScript('vendor/blockly/blocks_compressed.js');
      await loadScript('vendor/blockly/msg/en.js');
      defineBlocks();
      registerRenderer();
      PAPER_THEME = theme(false);
      NAVY = theme(true);
      cpp = makeGenerator();
    } else {
      await loadScript('vendor/monaco/vs/loader.js');
      await new Promise((resolve, reject) => {
        window.require.config({ paths: { vs: 'vendor/monaco/vs' } });
        window.require(['vs/editor/editor.main'], resolve, reject);
      });
      defineMonacoThemes();
      registerProviders();
    }
  })();

  window.rcEditor = {
    mode: MODE,
    ready,
    blocks: blocksApi,
    code: codeApi,
    // For checks: the C++ for a saved workspace, without showing it.
    generateFor(json, optionsJson) {
      blocksOptions(JSON.parse(optionsJson || '{}'));
      const headless = new Blockly.Workspace();
      Blockly.serialization.workspaces.load(JSON.parse(json), headless);
      headless.getAllBlocks(false).forEach((b) => {
        const root = b.getRootBlock();
        if (!HATS.includes(root.type) && b.setDisabledReason) b.setDisabledReason(true, 'ORPHANED_BLOCK');
      });
      const code = generate(headless);
      headless.dispose();
      return code;
    },
  };
})();
