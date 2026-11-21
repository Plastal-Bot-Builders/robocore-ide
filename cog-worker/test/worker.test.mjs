// The Cog Worker (cog-worker/src/index.js) in Node against a fake Anthropic API (no key, no network): the same
// answers as the server's Cog routes, the school key, the limits, CORS, and the way to a compile server.
// Run: node --test cog-worker/test/worker.test.mjs   (after `npm ci` in server/, which has the Anthropic SDK)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import worker from '../src/index.js';
import { CogQuota, take } from '../src/quota.js';

let api, apiBase, compile, compileBase;
const seen = []; // requests the fake API received

function sse(res, events) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const e of events) res.write(`event: ${e.type}\ndata: ${JSON.stringify(e)}\n\n`);
  res.end();
}

function message(text, stop = 'end_turn') {
  return {
    id: 'msg_test', type: 'message', role: 'assistant', model: 'claude-opus-5-5',
    content: [{ type: 'text', text }], stop_reason: stop, stop_sequence: null, stop_details: null,
    usage: { input_tokens: 10, output_tokens: 5 },
  };
}

before(async () => {
  // The key must reach the API from the Worker's settings: on Cloudflare there is no process.env to fall back on.
  delete process.env.ANTHROPIC_API_KEY;
  api = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      const body = JSON.parse(raw);
      seen.push({ path: req.url, headers: req.headers, body });
      if (body.stream) {
        return sse(res, [
          { type: 'message_start', message: { ...message(''), content: [], stop_reason: null } },
          { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
          { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'Names in Arduino ' } },
          { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'are case-sensitive.' } },
          { type: 'content_block_stop', index: 0 },
          { type: 'message_delta', delta: { stop_reason: 'end_turn', stop_sequence: null }, usage: { output_tokens: 5 } },
          { type: 'message_stop' },
        ]);
      }
      const out = { explanation: 'digitalWrite needs a capital W.', file: 'Blink.ino', newContent: 'void setup() {}\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); }\n' };
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(message(JSON.stringify(out))));
    });
  });
  await new Promise((r) => api.listen(0, '127.0.0.1', r));
  apiBase = `http://127.0.0.1:${api.address().port}`;

  compile = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ from: 'compile server', method: req.method, path: req.url }));
  });
  await new Promise((r) => compile.listen(0, '127.0.0.1', r));
  compileBase = `http://127.0.0.1:${compile.address().port}`;
});
after(() => { api.close(); compile.close(); });

const SCHOOL = 'test-school-key';
// Each test gets its own settings object, so its limits start from zero.
const env = (over = {}) => ({ ANTHROPIC_API_KEY: 'test-key', ANTHROPIC_BASE_URL: apiBase, COG_KEYS: `other-school,${SCHOOL}`, COG_RATE_PER_MIN: '1000', ...over });
const blink = 'void setup() {}\nvoid loop() { digitalwrite(LED_BUILTIN, HIGH); }\n';
const job = (over = {}) => ({
  style: 'hints',
  task: 'chat',
  messages: [{ role: 'user', content: 'Why does it not compile?' }],
  context: {
    read: true, project: 'Blink LED', board: 'RoboCore V2 (ESP32-S3)', editor: 'code',
    files: [{ name: 'Blink.ino', content: blink }],
    problems: [{ file: 'Blink.ino', line: 2, column: 15, severity: 'error', message: "'digitalwrite' was not declared in this scope" }],
  },
  ...over,
});
const call = (e, path, { method = 'GET', body, key = SCHOOL, ip = '203.0.113.7', origin, device } = {}) =>
  worker.fetch(new Request(`https://cog.example.workers.dev${path}`, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(key ? { 'X-Cog-Key': key } : {}),
      ...(ip ? { 'CF-Connecting-IP': ip } : {}),
      ...(origin ? { Origin: origin } : {}),
      ...(device ? { 'X-Cog-Device': device } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), e, { waitUntil() {} });
const events = async (r) => (await r.text()).split('\n\n').filter((l) => l.startsWith('data: ')).map((l) => JSON.parse(l.slice(6)));

test('health says Cog is ready, which model it uses and that it needs a school key', async () => {
  const j = await (await call(env(), '/health', { key: null })).json();
  assert.deepEqual(j.cog, { ready: true, model: 'claude-haiku-5-5', keys: true, open: false, by: { label: 'Claude, made by Anthropic', company: 'Anthropic', where: 'the United States', local: false } });
  assert.equal(j.compile, false);
  const off = await (await call(env({ ANTHROPIC_API_KEY: '' }), '/health')).json();
  assert.equal(off.cog.ready, false);
});

test('Test Cog: a school key gets in, a wrong or missing one does not', async () => {
  const e = env();
  assert.equal((await call(e, '/cog/key')).status, 200);
  assert.equal((await call(e, '/cog/key', { key: 'wrong' })).status, 401);
  const none = await call(e, '/cog/key', { key: null });
  assert.equal(none.status, 401);
  assert.match((await none.json()).error, /school key/);
});

test('chat streams the reply as server-sent events, with the key from the Worker settings', async () => {
  seen.length = 0;
  const r = await call(env(), '/cog/chat', { method: 'POST', body: job() });
  assert.equal(r.status, 200);
  assert.match(r.headers.get('Content-Type'), /text\/event-stream/);
  const ev = await events(r);
  assert.equal(ev.filter((e) => e.t === 'text').map((e) => e.v).join(''), 'Names in Arduino are case-sensitive.');
  assert.equal(ev.at(-1).t, 'done');
  assert.equal(seen.length, 1);
  assert.equal(seen[0].headers['x-api-key'], 'test-key');
  assert.equal(seen[0].body.stream, true);
  assert.match(JSON.stringify(seen[0].body.system), /You are Cog/);
});

test('fix answers with the smallest change as JSON', async () => {
  const r = await call(env(), '/cog/fix', { method: 'POST', body: job({ task: undefined }) });
  assert.equal(r.status, 200, await r.clone().text());
  const fix = await r.json();
  assert.equal(fix.file, 'Blink.ino');
  assert.match(fix.newContent, /digitalWrite/);
});

test('without an API key Cog answers 503 and says what is missing', async () => {
  const r = await call(env({ ANTHROPIC_API_KEY: '' }), '/cog/chat', { method: 'POST', body: job() });
  assert.equal(r.status, 503);
  assert.match((await r.json()).error, /ANTHROPIC_API_KEY/);
});

test('without school keys Cog stays closed', async () => {
  const r = await call(env({ COG_KEYS: '' }), '/cog/key');
  assert.equal(r.status, 503);
  assert.match((await r.json()).error, /COG_KEYS/);
});

test('the web IDE may call it; other sites may not', async () => {
  const e = env();
  const pre = await call(e, '/cog/chat', { method: 'OPTIONS', origin: 'https://plastal-bot-builders.github.io', key: null });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get('Access-Control-Allow-Origin'), 'https://plastal-bot-builders.github.io');
  assert.match(pre.headers.get('Access-Control-Allow-Headers'), /X-Cog-Key/);
  assert.equal((await call(e, '/cog/chat', { method: 'OPTIONS', origin: 'https://evil.example', key: null })).status, 403);
  assert.equal((await call(e, '/cog/chat', { method: 'POST', body: job(), origin: 'https://evil.example' })).status, 403);
  // The desktop apps send no Origin.
  assert.equal((await call(e, '/cog/key')).status, 200);
});

test('each address is limited, using the address Cloudflare saw', async () => {
  const e = env({ COG_RATE_PER_MIN: '2' });
  assert.equal((await call(e, '/cog/key')).status, 200);
  assert.equal((await call(e, '/cog/key')).status, 200);
  const third = await call(e, '/cog/key');
  assert.equal(third.status, 429);
  assert.equal(third.headers.get('Retry-After'), '60');
  assert.equal((await call(e, '/cog/key', { ip: '198.51.100.9' })).status, 200);
});

test('a school key is limited however many addresses use it', async () => {
  const e = env({ COG_KEY_RATE_PER_MIN: '1' });
  assert.equal((await call(e, '/cog/chat', { method: 'POST', body: job(), ip: '198.51.100.1' })).status, 200);
  const second = await call(e, '/cog/chat', { method: 'POST', body: job(), ip: '198.51.100.2' });
  assert.equal(second.status, 429);
  assert.match((await second.json()).error, /school/);
  assert.equal((await call(e, '/cog/chat', { method: 'POST', body: job(), key: 'other-school', ip: '198.51.100.3' })).status, 200);
});

test('a request that is not JSON or not a Cog job is refused', async () => {
  const e = env();
  const notJson = await worker.fetch(new Request('https://cog.example.workers.dev/cog/chat', {
    method: 'POST', headers: { 'X-Cog-Key': SCHOOL, 'Content-Type': 'text/plain' }, body: 'hello',
  }), e, {});
  assert.equal(notJson.status, 415);
  const unknown = await call(e, '/cog/chat', { method: 'POST', body: job({ task: 'explode' }) });
  assert.equal(unknown.status, 400);
  assert.match((await unknown.json()).error, /Unknown task/);
  assert.equal((await call(e, '/cog/nope', { method: 'POST', body: job() })).status, 404);
});

test('anything else goes to the compile server when one is set, or is answered 404', async () => {
  const alone = await call(env(), '/compile', { method: 'POST', body: { board: 'v2', files: [] }, key: null });
  assert.equal(alone.status, 404);
  assert.match((await alone.json()).error, /Cog only/);
  const passed = await call(env({ COMPILE_SERVER: `${compileBase}/` }), '/compile?x=1', { method: 'POST', body: { board: 'v2', files: [] }, key: null });
  assert.equal(passed.status, 200);
  assert.deepEqual(await passed.json(), { from: 'compile server', method: 'POST', path: '/compile?x=1' });
});

// ---- Open to everyone (COG_OPEN=1): no school key, daily limits counted by the QUOTA Durable Object ----

// A stand-in for the QUOTA binding: the real CogQuota over storage kept in a Map, as Durable Object storage behaves.
function fakeQuota() {
  const map = new Map();
  const storage = {
    async get(k) { return Array.isArray(k) ? new Map(k.filter((x) => map.has(x)).map((x) => [x, map.get(x)])) : map.get(k); },
    async put(k, v) { if (typeof k === 'object') for (const [a, b] of Object.entries(k)) map.set(a, b); else map.set(k, v); },
    async deleteAll() { map.clear(); },
  };
  const object = new CogQuota({ storage });
  return { map, storage, idFromName: (n) => n, get: () => ({ fetch: (url, init) => object.fetch(new Request(url, init)) }) };
}
const open = (over = {}) => env({ COG_OPEN: '1', COG_KEYS: SCHOOL, QUOTA: fakeQuota(), ...over });
const ask = (e, opts = {}) => call(e, '/cog/chat', { method: 'POST', body: job(), key: null, ...opts });

test('open: anyone may ask without a school key, and health says so', async () => {
  const e = open();
  const h = await (await call(e, '/health', { key: null })).json();
  assert.equal(h.cog.keys, false);
  assert.equal(h.cog.open, true);
  const r = await ask(e, { device: 'device-aaaa-1111' });
  assert.equal(r.status, 200, await r.clone().text());
  assert.equal((await events(r)).at(-1).t, 'done');
});

test('open: each computer gets its questions for the day, then hears it is back tomorrow', async () => {
  const e = open({ COG_DEVICE_DAY_LIMIT: '2' });
  assert.equal((await ask(e, { device: 'device-aaaa-1111' })).status, 200);
  assert.equal((await ask(e, { device: 'device-aaaa-1111' })).status, 200);
  const third = await ask(e, { device: 'device-aaaa-1111' });
  assert.equal(third.status, 429);
  assert.match((await third.json()).error, /on this computer today\. It will be back tomorrow/);
  assert.ok(Number(third.headers.get('Retry-After')) >= 60);
  // Another computer behind the same address still may.
  assert.equal((await ask(e, { device: 'device-bbbb-2222' })).status, 200);
});

test('open: one internet address and everyone together have their own limits', async () => {
  const e = open({ COG_ADDRESS_DAY_LIMIT: '2' });
  assert.equal((await ask(e, { device: 'device-aaaa-1111' })).status, 200);
  assert.equal((await ask(e, { device: 'device-bbbb-2222' })).status, 200);
  const third = await ask(e, { device: 'device-cccc-3333' });
  assert.equal(third.status, 429);
  assert.match((await third.json()).error, /this internet connection/);

  const all = open({ COG_DAY_LIMIT: '3' });
  for (const n of [1, 2, 3]) assert.equal((await ask(all, { device: `device-${n}-abcd`, ip: `198.51.100.${n}` })).status, 200);
  const fourth = await ask(all, { device: 'device-4-abcd', ip: '198.51.100.4' });
  assert.equal(fourth.status, 429);
  assert.match((await fourth.json()).error, /all the questions it can for today/);
});

test('open: a school key skips the daily limits', async () => {
  const e = open({ COG_DAY_LIMIT: '1' });
  assert.equal((await ask(e, { device: 'device-aaaa-1111' })).status, 200);
  assert.equal((await ask(e, { device: 'device-aaaa-1111' })).status, 429);
  assert.equal((await ask(e, { device: 'device-aaaa-1111', key: SCHOOL })).status, 200);
  assert.equal((await ask(e, { device: 'device-aaaa-1111', key: SCHOOL })).status, 200);
  // A wrong key is treated as no key: it is let in, within the limits.
  assert.equal((await ask(e, { device: 'device-bbbb-2222', key: 'wrong' })).status, 429);
});

test('open: a refused request is not counted, and an IDE that sends no device number counts by its address', async () => {
  const e = open({ COG_DEVICE_DAY_LIMIT: '1' });
  const bad = await call(e, '/cog/chat', { method: 'POST', body: job({ task: 'explode' }), key: null, device: 'device-aaaa-1111' });
  assert.equal(bad.status, 400);
  assert.equal((await ask(e, { device: 'device-aaaa-1111' })).status, 200);

  const old = open({ COG_DEVICE_DAY_LIMIT: '1' });
  assert.equal((await ask(old, { device: 'bad id!' })).status, 200);
  assert.equal((await ask(old)).status, 429); // the same address: the same "computer"
  assert.equal((await ask(old, { ip: '198.51.100.77' })).status, 200);
});

test('open: the counts hold no address or device number, and a new day starts from nothing', async () => {
  const e = open();
  await ask(e, { device: 'device-aaaa-1111', ip: '203.0.113.99' });
  const saved = JSON.stringify([...e.QUOTA.map]);
  assert.doesNotMatch(saved, /203\.0\.113\.99|device-aaaa-1111/);
  assert.equal(e.QUOTA.map.get('all'), 1);

  const { storage } = fakeQuota();
  const limits = { all: 1, device: 1, address: 1 };
  assert.equal((await take(storage, { day: '2026-11-21', device: 'd', address: 'a', limits })).ok, true);
  assert.equal((await take(storage, { day: '2026-11-21', device: 'd', address: 'a', limits })).ok, false);
  assert.equal((await take(storage, { day: '2026-11-22', device: 'd', address: 'a', limits })).ok, true);
});

test('open without the QUOTA object refuses rather than run without limits', async () => {
  const r = await ask(open({ QUOTA: undefined }), { device: 'device-aaaa-1111' });
  assert.equal(r.status, 503);
  assert.match((await r.json()).error, /daily limits/);
});
