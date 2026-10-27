// Cog routes against a fake Anthropic API (no key, no network): what the server sends to the API,
// and what it sends back to the IDE.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createServer, loadConfig } from '../src/server.js';
import { cogConfig } from '../src/cog.js';

let api, apiBase, server, base, offline, offlineBase;
const seen = []; // requests the fake API received
let next = {}; // how the fake API answers the next request: { refuse, fix, check }

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
  api = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      const body = JSON.parse(raw);
      seen.push({ path: req.url, headers: req.headers, body });
      const how = next;
      next = {};
      if (body.stream) {
        const stop = how.refuse ? 'refusal' : 'end_turn';
        return sse(res, [
          { type: 'message_start', message: { ...message(''), content: [], stop_reason: null } },
          { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
          { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'Names in Arduino ' } },
          { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'are case-sensitive.' } },
          { type: 'content_block_stop', index: 0 },
          { type: 'message_delta', delta: { stop_reason: stop, stop_sequence: null }, usage: { output_tokens: 5 } },
          { type: 'message_stop' },
        ]);
      }
      const props = body.output_config?.format?.schema?.properties ?? {};
      let out;
      if ('newContent' in props) {
        out = how.fix ?? { explanation: 'digitalWrite needs a capital W.', file: 'Blink.ino', newContent: 'void setup() {}\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); }\n' };
      } else {
        out = how.check ?? { question: 'Which line compiles?', options: ['delay(1000);', 'Delay(1000);'], answer: 0, explanation: 'delay is all lower case.', concept: 'Names are case-sensitive' };
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(message(JSON.stringify(out))));
    });
  });
  await new Promise((r) => api.listen(0, '127.0.0.1', r));
  apiBase = `http://127.0.0.1:${api.address().port}`;

  const cog = { ready: true, model: 'claude-opus-5-5', effort: 'low', fixEffort: 'medium', ratePerMin: 1000, baseURL: apiBase, apiKey: 'test-key', keys: [SCHOOL] };
  server = createServer(loadConfig({ port: 0, cli: 'false', cog, allowedOrigins: ['http://localhost:*'] }));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;

  offline = createServer(loadConfig({ port: 0, cli: 'false', cog: { ...cog, ready: false } }));
  await new Promise((r) => offline.listen(0, '127.0.0.1', r));
  offlineBase = `http://127.0.0.1:${offline.address().port}`;
});
after(() => { server.close(); offline.close(); api.close(); });

const SCHOOL = 'test-school-key';
const blink = 'void setup() {}\nvoid loop() { digitalwrite(LED_BUILTIN, HIGH); }\n';
const job = (over = {}) => ({
  style: 'hints',
  task: 'chat',
  messages: [{ role: 'user', content: 'Why does it not compile?' }],
  context: {
    project: 'Blink LED', board: 'RoboCore V2 (ESP32-S3)', editor: 'code',
    files: [{ name: 'Blink.ino', content: blink }],
    problems: [{ file: 'Blink.ino', line: 2, column: 15, severity: 'error', message: "'digitalwrite' was not declared in this scope" }],
  },
  ...over,
});
const post = (path, body, url = base, key = SCHOOL) => fetch(`${url}${path}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:8686', ...(key ? { 'X-Cog-Key': key } : {}) },
  body: JSON.stringify(body),
});
const events = async (r) => (await r.text()).split('\n\n').filter((l) => l.startsWith('data: ')).map((l) => JSON.parse(l.slice(6)));

test('health says whether Cog is ready and which model it uses', async () => {
  assert.deepEqual((await (await fetch(`${base}/health`)).json()).cog, { ready: true, model: 'claude-opus-5-5', keys: true });
  assert.equal((await (await fetch(`${offlineBase}/health`)).json()).cog.ready, false);
});

test('chat streams the reply as server-sent events', async () => {
  const r = await post('/cog/chat', job());
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-type'), /text\/event-stream/);
  assert.equal(r.headers.get('access-control-allow-origin'), 'http://localhost:8686');
  const ev = await events(r);
  assert.equal(ev.filter((e) => e.t === 'text').map((e) => e.v).join(''), 'Names in Arduino are case-sensitive.');
  assert.deepEqual(ev.at(-1), { t: 'done', stop: 'end_turn' });
});

test('the API request: model, fallback, effort, cached system prompt, project context and help style', async () => {
  await events(await post('/cog/chat', job()));
  const { path, headers, body } = seen.at(-1);
  assert.match(path, /^\/v1\/messages/);
  assert.equal(headers['x-api-key'], 'test-key');
  assert.match(headers['anthropic-beta'], /server-side-fallback-2026-07-01/);
  assert.equal(body.model, 'claude-opus-5-5');
  assert.equal(body.fallbacks, 'default');
  assert.equal(body.stream, true);
  assert.deepEqual(body.output_config, { effort: 'low' });
  assert.deepEqual(body.cache_control, { type: 'ephemeral' });
  assert.match(body.system, /^You are Cog/);
  assert.match(body.system, /trusted adult/, 'the safeguarding rule');
  assert.match(body.system, /You are an AI, not a person/);
  assert.equal(body.thinking, undefined, 'Opus 5.5 thinking is always on: no thinking setting is sent');
  const last = body.messages.at(-1);
  assert.equal(last.role, 'user');
  const text = last.content.map((b) => b.text).join('\n');
  assert.match(text, /<file name="Blink.ino">[\s\S]*digitalwrite/);
  assert.match(text, /Blink.ino:2:15 error: 'digitalwrite' was not declared/);
  assert.match(text, /Help style: Hints first/);
  assert.match(text, /The student: Why does it not compile\?/);
});

test('the explanation level reaches the model (Beginner when missing or unknown)', async () => {
  await events(await post('/cog/chat', job({ level: 'advanced' })));
  assert.match(JSON.stringify(seen.at(-1).body.messages.at(-1)), /Explanation level: Advanced/);
  await events(await post('/cog/chat', job({ level: 'wizard' })));
  assert.match(JSON.stringify(seen.at(-1).body.messages.at(-1)), /Explanation level: Beginner/);
  assert.match(seen.at(-1).body.system, /explanation level/);
});

test('with "Let Cog read this project" off, no code is sent', async () => {
  await events(await post('/cog/chat', job({ context: { read: false, files: [{ name: 'Blink.ino', content: 'SECRET_CODE' }] } })));
  const text = JSON.stringify(seen.at(-1).body.messages);
  assert.ok(!text.includes('SECRET_CODE'));
  assert.match(text, /cannot see their code/);
});

test('hint requests carry the hint number; earlier turns are kept', async () => {
  const msgs = [{ role: 'user', content: 'Explain this error' }, { role: 'assistant', content: 'Look at line 2.' }, { role: 'user', content: 'Another hint please' }];
  await events(await post('/cog/chat', job({ task: 'hint', hint: 2, messages: msgs })));
  const body = seen.at(-1).body;
  assert.equal(body.messages.length, 3);
  assert.equal(body.messages[1].content, 'Look at line 2.');
  assert.match(JSON.stringify(body.messages[2]), /hint 2/);
});

test('a refusal is passed on to the IDE', async () => {
  next = { refuse: true };
  const ev = await events(await post('/cog/chat', job()));
  assert.ok(ev.some((e) => e.t === 'refusal'));
});

test('fix returns the whole new file, using structured output', async () => {
  const r = await post('/cog/fix', job());
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.file, 'Blink.ino');
  assert.match(j.newContent, /digitalWrite/);
  const body = seen.at(-1).body;
  assert.equal(body.output_config.effort, 'medium');
  assert.equal(body.output_config.format.type, 'json_schema');
  assert.equal(body.output_config.format.schema.additionalProperties, false);
});

test('a fix for a file that is not in the project is rejected', async () => {
  next = { fix: { explanation: 'x', file: 'Other.ino', newContent: 'x' } };
  const r = await post('/cog/fix', job());
  assert.equal(r.status, 502);
});

test('a fix needs the project', async () => {
  const r = await post('/cog/fix', job({ context: { read: false } }));
  assert.equal(r.status, 400);
});

test('check returns one multiple-choice question; a bad answer index is rejected', async () => {
  const j = await (await post('/cog/check', job())).json();
  assert.equal(j.options.length, 2);
  assert.equal(j.answer, 0);
  assert.equal(j.concept, 'Names are case-sensitive');
  next = { check: { question: 'q', options: ['a', 'b'], answer: 5, explanation: 'e', concept: 'c' } };
  assert.equal((await post('/cog/check', job())).status, 502);
});

test('a model without the refusal fallback (Claude Haiku 5.5) is asked without it', async () => {
  const haiku = createServer(loadConfig({ port: 0, cli: 'false', cog: { ready: true, model: 'claude-haiku-5-5', effort: 'low', fixEffort: 'medium', ratePerMin: 1000, baseURL: apiBase, apiKey: 'k', keys: [SCHOOL] } }));
  await new Promise((r) => haiku.listen(0, '127.0.0.1', r));
  try {
    await events(await post('/cog/chat', job(), `http://127.0.0.1:${haiku.address().port}`));
    const { headers, body } = seen.at(-1);
    assert.equal(body.model, 'claude-haiku-5-5');
    assert.equal(body.fallbacks, undefined);
    assert.doesNotMatch(String(headers['anthropic-beta'] ?? ''), /server-side-fallback/);
  } finally {
    haiku.close();
  }
});

test('limits and errors', async () => {
  const many = Array.from({ length: 40 }, () => ({ role: 'user', content: 'hi' }));
  assert.equal((await post('/cog/chat', job({ messages: many }))).status, 413);
  assert.equal((await post('/cog/chat', job({ task: 'write_my_essay' }))).status, 400);
  assert.equal((await post('/cog/nope', job())).status, 404);
  const r = await post('/cog/chat', job(), offlineBase);
  assert.equal(r.status, 503);
  assert.match((await r.json()).error, /ANTHROPIC_API_KEY/);
});

test('only a school key gets an answer, so nobody else spends the API credit', async () => {
  const asked = seen.length;
  let r = await post('/cog/chat', job(), base, '');
  assert.equal(r.status, 401);
  assert.match((await r.json()).error, /needs a school key/);
  r = await post('/cog/fix', job(), base, 'guess');
  assert.equal(r.status, 401);
  assert.match((await r.json()).error, /not right/);
  assert.equal(seen.length, asked, 'nothing reached the API');

  assert.equal((await fetch(`${base}/cog/key`, { headers: { 'X-Cog-Key': SCHOOL } })).status, 200);
  assert.equal((await fetch(`${base}/cog/key`, { headers: { 'X-Cog-Key': 'guess' } })).status, 401);
  const pre = await fetch(`${base}/cog/chat`, { method: 'OPTIONS', headers: { Origin: 'http://localhost:8686' } });
  assert.match(pre.headers.get('access-control-allow-headers'), /X-Cog-Key/);
});

test('without school keys Cog stays shut, unless COG_OPEN=1', async () => {
  const cfg = { ready: true, model: 'claude-opus-5-5', effort: 'low', fixEffort: 'medium', ratePerMin: 1000, baseURL: apiBase, apiKey: 'k' };
  const shut = createServer(loadConfig({ port: 0, cli: 'false', cog: { ...cfg, keys: [] } }));
  const open = createServer(loadConfig({ port: 0, cli: 'false', cog: { ...cfg, keys: [], open: true } }));
  await new Promise((r) => shut.listen(0, '127.0.0.1', r));
  await new Promise((r) => open.listen(0, '127.0.0.1', r));
  try {
    const r = await post('/cog/chat', job(), `http://127.0.0.1:${shut.address().port}`, '');
    assert.equal(r.status, 503);
    assert.match((await r.json()).error, /COG_KEYS/);
    const ok = await post('/cog/chat', job(), `http://127.0.0.1:${open.address().port}`, '');
    assert.equal(ok.status, 200);
    await ok.text();
    assert.equal((await (await fetch(`http://127.0.0.1:${open.address().port}/health`)).json()).cog.keys, false);
  } finally {
    shut.close();
    open.close();
  }
});

test('COG_KEYS is read as a comma-separated list', () => {
  assert.deepEqual(cogConfig({ COG_KEYS: ' lusaka-1, ndola-2 ,,' }).keys, ['lusaka-1', 'ndola-2']);
  assert.equal(cogConfig({}).open, false);
  assert.equal(cogConfig({ COG_OPEN: '1' }).open, true);
});
