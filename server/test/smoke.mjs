#!/usr/bin/env node
// End-to-end check of a running compile server with the REAL arduino-cli (used in CI after docker run).
//   node server/test/smoke.mjs http://localhost:8080
// Compiles every RoboCore example for the V2, checks the ESP32 image headers,
// checks that a broken sketch reports the right file and line, and builds Blink for the Uno.
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const base = process.argv[2] || 'http://localhost:8080';
const here = path.dirname(fileURLToPath(import.meta.url));
const examples = path.join(here, '..', '..', 'firmware', 'RoboCore', 'examples');

async function compile(board, files) {
  const r = await fetch(`${base}/compile`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ board, files }) });
  const j = await r.json();
  if (r.status !== 200) throw new Error(`HTTP ${r.status}: ${j.error}`);
  return j;
}

let failed = 0;
const check = async (name, fn) => {
  const t0 = Date.now();
  try {
    await fn();
    console.log(`ok    ${name} (${((Date.now() - t0) / 1000).toFixed(1)} s)`);
  } catch (e) {
    failed++;
    console.log(`FAIL  ${name}: ${e.message}`);
  }
};

await check('health', async () => {
  const h = await (await fetch(`${base}/health`)).json();
  assert.equal(h.ok, true);
  console.log(`      arduino-cli ${h.arduinoCli}, cores ${h.cores.join(', ')}`);
});

for (const name of readdirSync(examples).sort()) {
  await check(`v2 ${name}`, async () => {
    const content = readFileSync(path.join(examples, name, `${name}.ino`), 'utf8');
    const j = await compile('v2', [{ name: `${name}.ino`, content }, { name: 'config.h', content: '#pragma once\n#define BAUD_RATE 115200\n' }]);
    if (!j.ok) throw new Error(j.problems.map((p) => `${p.file}:${p.line} ${p.message}`).join(' | ') || j.log.slice(-800));
    const parts = Object.fromEntries(j.image.parts.map((p) => [p.name, { ...p, bytes: Buffer.from(p.data, 'base64') }]));
    assert.deepEqual(j.image.parts.map((p) => p.offset), [0x0, 0x8000, 0xe000, 0x10000]);
    assert.equal(parts.bootloader.bytes[0], 0xe9, 'bootloader image magic');
    assert.equal(parts.app.bytes[0], 0xe9, 'app image magic');
    assert.equal(parts.app.bytes[12], 0x09, 'app chip id is ESP32-S3');
    assert.deepEqual([...parts.partitions.bytes.subarray(0, 2)], [0xaa, 0x50], 'partition table magic');
    assert.ok(j.sizes.flash?.used > 100_000, 'flash size reported');
    const warn = j.problems.filter((p) => p.severity === 'warning' && p.file !== 'library');
    if (warn.length) console.log(`      warnings: ${warn.map((p) => `${p.file}:${p.line} ${p.message}`).join(' | ')}`);
  });
}

await check('v2 error points at the right line', async () => {
  const j = await compile('v2', [{ name: 'Broken.ino', content: 'void setup() {}\n\nvoid loop() {\n  notAFunction();\n}\n' }]);
  assert.equal(j.ok, false);
  const e = j.problems.find((p) => p.severity === 'error');
  assert.equal(e.file, 'Broken.ino');
  assert.equal(e.line, 4);
  assert.match(e.message, /notAFunction/);
  assert.ok(!/\/home\/|\/tmp\/rc-/.test(j.log), 'no server paths in the log');
});

await check('v2 missing loop()', async () => {
  const j = await compile('v2', [{ name: 'NoLoop.ino', content: 'void setup() {}\n' }]);
  assert.equal(j.ok, false);
  assert.ok(j.problems.some((p) => /loop/.test(p.message)), JSON.stringify(j.problems));
});

await check('uno Blink', async () => {
  const content = readFileSync(path.join(examples, 'Blink', 'Blink.ino'), 'utf8');
  const j = await compile('uno', [{ name: 'Blink.ino', content }]);
  assert.equal(j.ok, true, j.log.slice(-500));
  assert.equal(j.image.format, 'hex');
  assert.match(j.image.data, /^:/);
});

if (failed) {
  console.log(`\n${failed} check(s) failed`);
  process.exit(1);
}
console.log('\nall smoke checks passed');
