import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, chmod, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer, loadConfig } from '../src/server.js';
import { validateRequest } from '../src/compile.js';
import { parseDiagnostics, parseSizes, parseCliJson, scrub, mergeProblems } from '../src/parse.js';

const here = path.dirname(fileURLToPath(import.meta.url));
let server, base, tmp;

before(async () => {
  tmp = await mkdtemp(path.join(os.tmpdir(), 'rc-test-'));
  const bootApp0 = path.join(tmp, 'boot_app0.bin');
  await writeFile(bootApp0, Buffer.from([0x55, 0x55]));
  const cli = path.join(here, 'fake-arduino-cli.mjs');
  await chmod(cli, 0o755);
  const cfg = loadConfig({
    port: 0, cli, bootApp0, tmpDir: tmp, timeoutMs: 5000, ratePerMin: 1000, maxRunning: 1, maxQueued: 2,
    allowedOrigins: ['https://plastal-bot-builders.github.io', 'http://localhost:*'],
  });
  server = createServer(cfg);
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const post = (body, headers = {}) => fetch(`${base}/compile`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', ...headers },
  body: typeof body === 'string' ? body : JSON.stringify(body),
});
const blink = { board: 'v2', files: [{ name: 'Blink.ino', content: 'void setup(){}\nvoid loop(){}\n' }, { name: 'config.h', content: '#pragma once\n' }] };

test('compiles for the RoboCore V2 and returns the four flash parts', async () => {
  const r = await post(blink);
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.ok, true);
  assert.equal(j.image.format, 'esp32');
  assert.equal(j.image.chip, 'esp32s3');
  assert.deepEqual(j.image.parts.map((p) => [p.name, p.offset]), [['bootloader', 0], ['partitions', 0x8000], ['boot_app0', 0xe000], ['app', 0x10000]]);
  assert.equal(Buffer.from(j.image.parts[3].data, 'base64')[0], 0xe9);
  assert.deepEqual(j.sizes, { flash: { used: 289306, max: 3145728 }, ram: { used: 20118, max: 327680 } });
  assert.ok(!JSON.stringify(j).includes(tmp), 'server paths must not leak');
});

test('the old ESP32 boards put the bootloader at 0x1000', async () => {
  const j = await (await post({ ...blink, board: 'devkit' })).json();
  assert.equal(j.image.parts[0].offset, 0x1000);
});

test('Uno builds come back as Intel HEX', async () => {
  const j = await (await post({ ...blink, board: 'uno' })).json();
  assert.equal(j.image.format, 'hex');
  assert.match(j.image.data, /^:10/);
});

test('compile errors point at the user file and line, without server paths', async () => {
  const j = await (await post({ board: 'v2', files: [{ name: 'Bad.ino', content: 'void setup(){}\nvoid loop(){\n    foo(); // MAKE_ERROR\n}\n' }] })).json();
  assert.equal(j.ok, false);
  assert.equal(j.problems.length, 1);
  assert.deepEqual(j.problems[0], { severity: 'error', file: 'Bad.ino', line: 3, column: 5, message: "'foo' was not declared in this scope" });
  assert.ok(!j.log.includes(tmp));
  assert.match(j.log, /Bad\.ino:3:5/);
});

test('a missing loop() is explained', async () => {
  const j = await (await post({ board: 'v2', files: [{ name: 'NoLoop.ino', content: 'void setup(){} // MAKE_LINK' }] })).json();
  assert.equal(j.ok, false);
  assert.match(j.problems[0].message, /Every sketch needs a loop\(\) function/);
  assert.ok(!j.log.includes('/home/builder/.arduino15'), 'core path is hidden');
});

test('a sketch that takes too long is stopped', async () => {
  const r = await post({ board: 'v2', files: [{ name: 'Slow.ino', content: '// MAKE_SLOW' }] });
  assert.equal(r.status, 504);
  assert.match((await r.json()).error, /took longer/);
});

test('temporary folders are removed', async () => {
  const left = (await readdir(tmp)).filter((n) => n.startsWith('rc-'));
  assert.deepEqual(left, []);
});

test('rejects bad requests', async () => {
  const cases = [
    [{ board: 'nope', files: blink.files }, 400, /Unknown board/],
    [{ board: 'v2', files: [] }, 400, /at least one file/],
    [{ board: 'v2', files: [{ name: '../evil.ino', content: '' }] }, 400, /not an allowed file name/],
    [{ board: 'v2', files: [{ name: 'a.exe', content: '' }] }, 400, /not an allowed file name/],
    [{ board: 'v2', files: [{ name: 'x.h', content: '' }] }, 400, /one \.ino/],
    [{ board: 'v2', files: [{ name: 'A.ino', content: '' }, { name: 'a.ino', content: '' }] }, 400, /Two files/],
    [{ board: 'v2', files: [{ name: 'Big.ino', content: 'x'.repeat(200_001) }] }, 413, /too big/],
  ];
  for (const [body, status, msg] of cases) {
    const r = await post(body);
    assert.equal(r.status, status, JSON.stringify(body).slice(0, 60));
    assert.match((await r.json()).error, msg);
  }
  assert.equal((await post('{not json')).status, 400);
  assert.equal((await post(blink, { 'Content-Type': 'text/plain' })).status, 415);
});

test('CORS: the IDE site and localhost are allowed, other sites are not', async () => {
  let r = await fetch(`${base}/compile`, { method: 'OPTIONS', headers: { Origin: 'https://plastal-bot-builders.github.io' } });
  assert.equal(r.status, 204);
  assert.equal(r.headers.get('access-control-allow-origin'), 'https://plastal-bot-builders.github.io');
  r = await fetch(`${base}/compile`, { method: 'OPTIONS', headers: { Origin: 'http://localhost:5173' } });
  assert.equal(r.status, 204);
  r = await fetch(`${base}/compile`, { method: 'OPTIONS', headers: { Origin: 'https://evil.example' } });
  assert.equal(r.status, 403);
  r = await post(blink, { Origin: 'https://evil.example' });
  assert.equal(r.status, 403);
});

test('health and boards', async () => {
  const h = await (await fetch(`${base}/health`)).json();
  assert.equal(h.ok, true);
  const b = await (await fetch(`${base}/boards`)).json();
  assert.ok(b.boards.some((x) => x.id === 'v2' && x.fqbn.includes('PSRAM=enabled') && x.fqbn.includes('CDCOnBoot=cdc')));
});

test('validateRequest picks the main .ino', () => {
  const r = validateRequest({ board: 'v2', main: 'B.ino', files: [{ name: 'A.ino', content: '' }, { name: 'B.ino', content: '' }] });
  assert.equal(r.main, 'B.ino');
  assert.throws(() => validateRequest({ board: 'v2', main: 'C.ino', files: [{ name: 'A.ino', content: '' }] }), /not one of the \.ino files/);
  assert.throws(() => validateRequest({ board: '__proto__', files: [{ name: 'A.ino', content: '' }] }), /Unknown board/);
});

test('parsers', () => {
  const text = [
    "Blink.ino:12:5: error: 'x' was not declared in this scope",
    'Blink.ino:12:5: note: suggested alternative',
    "config.h:2:1: warning: extra tokens",
    "<RoboCore>/src/RoboCoreMotors.cpp:40:3: error: oops",
  ].join('\n');
  const p = parseDiagnostics(text, '', ['Blink.ino', 'config.h']);
  assert.equal(p.length, 3);
  assert.deepEqual(p[0], { severity: 'error', file: 'Blink.ino', line: 12, column: 5, message: "'x' was not declared in this scope" });
  assert.equal(p[1].severity, 'warning');
  assert.equal(p[2].file, 'library');
  assert.equal(p[2].source, 'src/RoboCoreMotors.cpp');
  assert.deepEqual(parseSizes(null, 'Sketch uses 10 bytes (1%) of program storage space. Maximum is 100 bytes.\nGlobal variables use 5 bytes (1%) of dynamic memory, leaving 1 bytes for local variables. Maximum is 50 bytes.'),
    { flash: { used: 10, max: 100 }, ram: { used: 5, max: 50 } });
  assert.deepEqual(parseCliJson('noise\n{"success":true}'), { success: true });
  assert.equal(parseCliJson('nothing'), null);
  assert.equal(scrub('/tmp/a/b.ino and /tmp/a', [['/tmp/a/', ''], ['/tmp/a', '']]), 'b.ino and ');
});

test('the same diagnostic from the JSON result and the text log is listed once', () => {
  const a = [{ severity: 'error', file: 'Blink.ino', line: 6, column: 3, message: "'digitalwrite' was not declared in this scope" }];
  const b = [{ severity: 'error', file: 'Blink.ino', line: 6, column: 3, message: "'digitalwrite' was not declared in this scope\n    6 |   digitalwrite(LED_BUILTIN, HIGH);" }];
  assert.deepEqual(mergeProblems(a, b), a);
});
