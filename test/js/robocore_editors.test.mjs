// Tests the IDE shortcuts in web/robocore_editors.js (Ctrl/⌘ + S, R, U, I typed inside Blockly or Monaco)
// in Node with a fake page: the editors themselves never load. Run: node --test test/js/robocore_editors.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.join(here, '../../web/robocore_editors.js'), 'utf8');

// Loads the script as the #code (or #blocks) page. Its script tags never finish loading, which is fine here.
function page(mode = 'code') {
  const listeners = [];
  const ctx = {
    location: { hash: '#' + mode },
    document: { createElement: () => ({}), head: { appendChild() {} } },
    addEventListener: (type, fn, capture) => listeners.push({ type, fn, capture }),
    setTimeout,
    clearTimeout,
    console,
  };
  ctx.window = ctx;
  vm.runInNewContext(source, ctx);
  const keydown = listeners.find((l) => l.type === 'keydown');
  assert.ok(keydown, 'a keydown listener on the window');
  assert.equal(keydown.capture, true, 'it listens in the capture phase, before Blockly or Monaco');
  const actions = [];
  ctx.rcEditor.setIdeKeys((a) => actions.push(a));
  const press = (init) => {
    const e = { key: '', code: '', ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, repeat: false, ...init };
    e.prevented = false;
    e.stopped = false;
    e.preventDefault = () => { e.prevented = true; };
    e.stopPropagation = () => { e.stopped = true; };
    keydown.fn(e);
    return e;
  };
  return { ctx, actions, press };
}

test('Ctrl or ⌘ + S, R, U, I go to the IDE and not to the editor or the browser', () => {
  const { actions, press } = page();
  for (const [key, mod] of [['s', 'ctrlKey'], ['r', 'ctrlKey'], ['u', 'metaKey'], ['i', 'metaKey'], ['S', 'ctrlKey']]) {
    const e = press({ key, code: 'Key' + key.toUpperCase(), [mod]: true });
    assert.ok(e.prevented && e.stopped, `${mod} + ${key} is taken`);
  }
  assert.deepEqual(actions, ['save', 'verify', 'upload', 'cog', 'save']);
});

test("the editors' own shortcuts and plain typing are left alone", () => {
  const { actions, press } = page();
  const passed = [
    { key: 'f', code: 'KeyF', ctrlKey: true }, // find
    { key: 'z', code: 'KeyZ', metaKey: true }, // undo
    { key: 'c', code: 'KeyC', ctrlKey: true }, // copy
    { key: ' ', code: 'Space', ctrlKey: true }, // suggestions
    { key: 's', code: 'KeyS' }, // typing an s
    { key: 'R', code: 'KeyR', ctrlKey: true, shiftKey: true }, // the browser's hard reload stays the browser's
    { key: 'i', code: 'KeyI', ctrlKey: true, altKey: true },
    { key: 'Meta', code: 'MetaLeft', metaKey: true },
  ];
  for (const init of passed) {
    const e = press(init);
    assert.ok(!e.prevented && !e.stopped, JSON.stringify(init));
  }
  assert.deepEqual(actions, []);
});

test('other keyboard layouts: the key position counts when the letter is not a Latin one', () => {
  const { actions, press } = page('blocks');
  press({ key: 'ы', code: 'KeyS', ctrlKey: true });
  press({ key: 'к', code: 'KeyR', ctrlKey: true });
  assert.deepEqual(actions, ['save', 'verify']);
});

test('a held key runs the action once; before the app has a handler the key is still taken', () => {
  const { ctx, actions, press } = page();
  press({ key: 'r', code: 'KeyR', ctrlKey: true });
  const held = press({ key: 'r', code: 'KeyR', ctrlKey: true, repeat: true });
  assert.ok(held.prevented, 'held Ctrl+R must not reload the page either');
  assert.deepEqual(actions, ['verify']);

  ctx.rcEditor.setIdeKeys(null);
  const e = press({ key: 'r', code: 'KeyR', ctrlKey: true });
  assert.ok(e.prevented, 'no page reload while the app is still starting');
  assert.deepEqual(actions, ['verify']);
});
