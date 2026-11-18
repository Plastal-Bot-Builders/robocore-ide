// Cog's second engine (COG_PROVIDER=openai) against a fake service that speaks the OpenAI chat format (no key, no
// network): a model on the school's own computer (Ollama …) or a host (DeepSeek, Cloudflare, Groq, OpenRouter …).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import { createServer, loadConfig } from '../src/server.js';
import { cogConfig, thinkFilter } from '../src/cog.js';
import worker from '../../cog-worker/src/index.js';

let api, apiBase, server, base;
const seen = []; // requests the fake service received
let next = {}; // how it answers the next request(s)
const quiet = console.error;

const FIX = { explanation: 'digitalWrite needs a capital W.', file: 'Blink.ino', newContent: 'void setup() {}\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); }\n' };
const CHECK = { question: 'Which line compiles?', options: ['delay(1000);', 'Delay(1000);'], answer: 0, explanation: 'delay is all lower case.', concept: 'Names are case-sensitive' };
const ENV = () => ({ COG_PROVIDER: 'openai', COG_BASE_URL: `${apiBase}/v1/`, COG_MODEL: 'gemma3', COG_LOCAL: '1', COG_OPEN: '1', COG_RATE_PER_MIN: '1000' });
const start = async (env) => {
  const s = createServer(loadConfig({ port: 0, cli: 'false', cog: cogConfig(env), allowedOrigins: ['http://localhost:*'] }));
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  return s;
};

before(async () => {
  console.error = () => {}; // the engine logs the service's errors for whoever runs the server
  api = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      const body = JSON.parse(raw);
      seen.push({ path: req.url, headers: req.headers, body });
      const how = next;
      if (!how.sticky) next = {};
      if (how.status) {
        res.writeHead(how.status, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: { message: 'no' } }));
      }
      if (how.reject?.includes(body.response_format?.type)) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: { message: `response_format ${body.response_format.type} is not supported` } }));
      }
      if (body.stream) {
        res.writeHead(200, { 'Content-Type': 'text/event-stream' });
        const pieces = how.pieces ?? ['Names in Arduino ', 'are case-sensitive.'];
        res.write(`data: ${JSON.stringify({ choices: [{ index: 0, delta: { role: 'assistant', content: '' } }] })}\n\n`);
        res.write(`data: ${JSON.stringify({ choices: [{ index: 0, delta: { reasoning_content: 'the student wrote a small w' } }] })}\n\n`);
        for (const p of pieces) res.write(`data: ${JSON.stringify({ choices: [{ index: 0, delta: { content: p } }] })}\n\n`);
        res.write(`data: ${JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: how.finish ?? 'stop' }] })}\n\n`);
        res.write('data: [DONE]\n\n');
        return res.end();
      }
      const wantsFix = /newContent/.test(body.messages.at(-1).content);
      const content = how.content ?? JSON.stringify(wantsFix ? FIX : CHECK);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ index: 0, message: { role: 'assistant', content }, finish_reason: how.finish ?? 'stop' }] }));
    });
  });
  await new Promise((r) => api.listen(0, '127.0.0.1', r));
  apiBase = `http://127.0.0.1:${api.address().port}`;
  server = await start(ENV());
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => { server.close(); api.close(); console.error = quiet; });

const blink = 'void setup() {}\nvoid loop() { digitalwrite(LED_BUILTIN, HIGH); }\n';
const job = (over = {}) => ({
  by: 'gemma3|||local', // who the IDE's notice named
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
const post = (path, body, url = base) => fetch(`${url}${path}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json', Origin: 'http://localhost:8686' }, body: JSON.stringify(body),
});
const events = async (r) => (await r.text()).split('\n\n').filter((l) => l.startsWith('data: ')).map((l) => JSON.parse(l.slice(6)));
const said = (ev) => ev.filter((e) => e.t === 'text').map((e) => e.v).join('');

test('settings: the address, the model and who answers are all needed', () => {
  const ok = cogConfig({ COG_PROVIDER: 'OpenAI', COG_BASE_URL: 'http://127.0.0.1:11434/v1/chat/completions', COG_MODEL: 'gemma3', COG_LOCAL: '1' });
  assert.equal(ok.ready, true);
  assert.equal(ok.baseURL, 'http://127.0.0.1:11434/v1');
  assert.deepEqual(ok.by, { label: 'gemma3', company: '', where: '', local: true });

  const hosted = cogConfig({ COG_PROVIDER: 'openai', COG_BASE_URL: 'https://api.deepseek.com', COG_MODEL: 'deepseek-flash', COG_API_KEY: 'k', COG_AI_NAME: 'DeepSeek', COG_AI_COMPANY: 'DeepSeek', COG_AI_WHERE: 'China' });
  assert.equal(hosted.ready, true);
  assert.deepEqual(hosted.by, { label: 'DeepSeek', company: 'DeepSeek', where: 'China', local: false });

  // A host without "who answers" stays shut: the IDE could not tell students where their words go.
  const unnamed = cogConfig({ COG_PROVIDER: 'openai', COG_BASE_URL: 'https://api.deepseek.com', COG_MODEL: 'deepseek-flash', COG_API_KEY: 'k' });
  assert.equal(unnamed.ready, false);
  assert.match(unnamed.missing.join(' '), /COG_AI_COMPANY and COG_AI_WHERE/);
  assert.match(cogConfig({ COG_PROVIDER: 'openai' }).missing.join(' '), /COG_BASE_URL.*COG_MODEL/);
  assert.equal(cogConfig({ ...ENV(), COG_EXTRA_BODY: '{not json' }).ready, false);
  assert.equal(cogConfig({ COG_PROVIDER: 'gemini', ANTHROPIC_API_KEY: 'k' }).ready, false, 'an unknown engine is not quietly replaced by Claude');
});

test('a server that is not set up says what is missing', async () => {
  const s = await start({ COG_PROVIDER: 'openai', COG_OPEN: '1' });
  try {
    const r = await post('/cog/chat', job(), `http://127.0.0.1:${s.address().port}`);
    assert.equal(r.status, 503);
    assert.match((await r.json()).error, /COG_BASE_URL, COG_MODEL/);
  } finally {
    s.close();
  }
});

test('health says who answers, for the IDE\'s notice', async () => {
  const { cog } = await (await fetch(`${base}/health`)).json();
  assert.deepEqual(cog, { ready: true, model: 'gemma3', keys: false, by: { label: 'gemma3', company: '', where: '', local: true } });
});

test('nothing goes to an AI the IDE\'s notice did not name', async () => {
  const at = seen.length;
  // An IDE from before the notice could change tells students "Claude": it gets no answer from another AI.
  const old = await post('/cog/chat', job({ by: undefined }));
  assert.equal(old.status, 409);
  assert.match((await old.json()).error, /newer RoboCore IDE/);
  // The server changed its AI since this device read the notice: the student reads the new one first.
  for (const path of ['/cog/chat', '/cog/fix', '/cog/check']) {
    const r = await post(path, job({ by: 'Claude, made by Anthropic|Anthropic|the United States|hosted' }));
    assert.equal(r.status, 409, path);
    assert.match((await r.json()).error, /Read the note/);
  }
  assert.equal(seen.length, at, 'the model was not asked');
});

test('chat: the request in the OpenAI chat format, and the reply streamed to the IDE', async () => {
  const r = await post('/cog/chat', job());
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-type'), /text\/event-stream/);
  const ev = await events(r);
  assert.equal(said(ev), 'Names in Arduino are case-sensitive.', 'the model\'s thinking (reasoning_content) is not passed on');
  assert.deepEqual(ev.at(-1), { t: 'done', stop: 'end_turn' });

  const { path, headers, body } = seen.at(-1);
  assert.equal(path, '/v1/chat/completions');
  assert.equal(headers.authorization, undefined, 'a model on this computer needs no key');
  assert.equal(body.model, 'gemma3');
  assert.equal(body.stream, true);
  assert.equal(body.messages[0].role, 'system');
  assert.match(body.messages[0].content, /^You are Cog/);
  assert.match(body.messages[0].content, /trusted adult/, 'the safeguarding rule');
  const last = body.messages.at(-1);
  assert.equal(last.role, 'user');
  assert.equal(typeof last.content, 'string');
  assert.match(last.content, /<file name="Blink.ino">[\s\S]*digitalwrite/);
  assert.match(last.content, /Help style: Hints first/);
  assert.match(last.content, /The student: Why does it not compile\?/);
});

test('with "Let Cog read this project" off, no code is sent', async () => {
  await events(await post('/cog/chat', job({ context: { ...job().context, read: false } })));
  const text = seen.at(-1).body.messages.at(-1).content;
  assert.doesNotMatch(text, /digitalwrite/);
  assert.match(text, /turned off "Let Cog read this project"/);
});

test('a host gets its key and the extra settings', async () => {
  const s = await start({ ...ENV(), COG_LOCAL: '', COG_API_KEY: 'sk-test', COG_AI_COMPANY: 'DeepSeek', COG_AI_WHERE: 'China', COG_EXTRA_BODY: '{"thinking":{"type":"disabled"}}' });
  try {
    await events(await post('/cog/chat', job({ by: 'gemma3|DeepSeek|China|hosted' }), `http://127.0.0.1:${s.address().port}`));
    const { headers, body } = seen.at(-1);
    assert.equal(headers.authorization, 'Bearer sk-test');
    assert.deepEqual(body.thinking, { type: 'disabled' });
    assert.equal(body.model, 'gemma3');
  } finally {
    s.close();
  }
});

test('thinking between <think> tags never reaches the student, however the text is cut up', async () => {
  next = { pieces: ['<thi', 'nk>The student wrote digital', 'write.</th', 'ink>\n\n', 'Look at ', 'line 2. Is 1 < 2?'] };
  assert.equal(said(await events(await post('/cog/chat', job()))), 'Look at line 2. Is 1 < 2?');

  const whole = 'A <b>bold</b> idea: <think>hidden</think>use `<` for less than. <';
  for (let size = 1; size <= whole.length; size++) {
    let out = '';
    const f = thinkFilter((t) => { out += t; });
    for (let i = 0; i < whole.length; i += size) f.push(whole.slice(i, i + size));
    f.end();
    assert.equal(out, 'A <b>bold</b> idea: use `<` for less than. <', `in pieces of ${size}`);
  }
});

test('an answer that was cut off or held back is passed on as such', async () => {
  next = { finish: 'length' };
  assert.deepEqual((await events(await post('/cog/chat', job()))).at(-1), { t: 'done', stop: 'max_tokens' });
  next = { finish: 'content_filter' };
  const ev = await events(await post('/cog/chat', job()));
  assert.equal(ev.at(-2).t, 'refusal');
  assert.deepEqual(ev.at(-1), { t: 'done', stop: 'refusal' });
});

test('fix asks for an object by JSON Schema and returns the whole new file', async () => {
  const r = await post('/cog/fix', job());
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), FIX);
  const { body } = seen.at(-1);
  assert.equal(body.stream, undefined);
  assert.equal(body.response_format.type, 'json_schema');
  assert.equal(body.response_format.json_schema.strict, true);
  assert.deepEqual(body.response_format.json_schema.schema.required, ['explanation', 'file', 'newContent']);
  assert.match(body.messages.at(-1).content, /Reply with one JSON object/);
});

test('a service that does not know JSON Schema is asked the next way, and that way is remembered', async () => {
  const s = await start(ENV());
  const url = `http://127.0.0.1:${s.address().port}`;
  try {
    next = { reject: ['json_schema'], sticky: true };
    const at = seen.length;
    assert.deepEqual(await (await post('/cog/fix', job(), url)).json(), FIX);
    assert.deepEqual(seen.slice(at).map((q) => q.body.response_format?.type), ['json_schema', 'json_object']);
    assert.deepEqual(await (await post('/cog/check', job(), url)).json(), CHECK);
    assert.equal(seen.length, at + 3, 'no second try with JSON Schema');
    assert.equal(seen.at(-1).body.response_format.type, 'json_object');

    // Nothing at all: the request goes without response_format, and the instructions alone ask for JSON.
    next = { reject: ['json_schema', 'json_object'], sticky: true };
    assert.deepEqual(await (await post('/cog/check', job(), url)).json(), CHECK);
    assert.equal(seen.at(-1).body.response_format, undefined);
  } finally {
    next = {};
    s.close();
  }
});

test('an object inside a code fence, after thinking, is still read; anything else is refused', async () => {
  next = { content: `<think>{"not": "this"}</think>Here is the fix:\n\`\`\`json\n${JSON.stringify(FIX)}\n\`\`\`\nGood luck!` };
  assert.deepEqual(await (await post('/cog/fix', job())).json(), FIX);

  next = { content: 'I think you should capitalise the W.' };
  const bad = await post('/cog/fix', job());
  assert.equal(bad.status, 502);
  assert.match((await bad.json()).error, /could not read/);

  next = { content: JSON.stringify({ ...FIX, file: 'Other.ino' }) };
  assert.match((await (await post('/cog/fix', job())).json()).error, /not in the project/);
  next = { content: JSON.stringify({ ...CHECK, answer: 5 }) };
  assert.equal((await post('/cog/check', job())).status, 502);
  next = { finish: 'length' };
  assert.match((await (await post('/cog/fix', job())).json()).error, /too long/);
});

test('errors from the service become plain messages for students', async () => {
  next = { status: 429 };
  const busy = await post('/cog/fix', job());
  assert.equal(busy.status, 429);
  assert.match((await busy.json()).error, /busy/);

  next = { status: 401 };
  assert.match((await (await post('/cog/fix', job())).json()).error, /API key/);

  next = { status: 404 };
  const ev = await events(await post('/cog/chat', job()));
  assert.deepEqual(ev.map((e) => e.t), ['error']);
  assert.match(ev[0].message, /address or model/);
  assert.doesNotMatch(JSON.stringify(ev), /"no"/, 'the service\'s own words stay on the server');
});

test('a model that is not running: the message says so', async () => {
  const gone = http.createServer();
  await new Promise((r) => gone.listen(0, '127.0.0.1', r));
  const dead = `http://127.0.0.1:${gone.address().port}/v1`;
  await new Promise((r) => gone.close(r));
  const s = await start({ ...ENV(), COG_BASE_URL: dead });
  try {
    const ev = await events(await post('/cog/chat', job(), `http://127.0.0.1:${s.address().port}`));
    assert.match(ev.at(-1).message, /Check that it is running/);
  } finally {
    s.close();
  }
});

test('a free allowance that is used up for the day is said plainly', async () => {
  next = { status: 429, sticky: true };
  try {
    const s = await start(ENV());
    try {
      const url = `http://127.0.0.1:${s.address().port}`;
      assert.match((await events(await post('/cog/chat', job(), url))).at(-1).message, /busy right now/);
    } finally {
      s.close();
    }
  } finally {
    next = {};
  }
  // Cloudflare's words when the daily free allowance is gone, whatever status they come with.
  for (const status of [429, 400]) {
    const quota = http.createServer((req, res) => {
      req.resume();
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ errors: [{ code: 4006, message: 'you have used up your daily free allocation of 10,000 neurons' }] }));
    });
    await new Promise((r) => quota.listen(0, '127.0.0.1', r));
    const s = await start({ ...ENV(), COG_BASE_URL: `http://127.0.0.1:${quota.address().port}/v1` });
    try {
      const url = `http://127.0.0.1:${s.address().port}`;
      assert.match((await events(await post('/cog/chat', job(), url))).at(-1).message, /for today\. It will be back tomorrow/);
      const fix = await post('/cog/fix', job(), url);
      assert.equal(fix.status, 429);
      assert.match((await fix.json()).error, /back tomorrow/);
    } finally {
      s.close();
      quota.close();
    }
  }
});

test('COG_JSON_MODE and the token caps: how the fix is asked for, and how long answers may be', async () => {
  assert.equal(cogConfig({ ...ENV(), COG_JSON_MODE: 'xml' }).ready, false);
  assert.equal(cogConfig({ ...ENV(), COG_MAX_TOKENS: 'lots' }).ready, false);
  const s = await start({ ...ENV(), COG_JSON_MODE: 'object', COG_MAX_TOKENS: '1500', COG_FIX_MAX_TOKENS: '6000' });
  const url = `http://127.0.0.1:${s.address().port}`;
  try {
    const at = seen.length;
    assert.deepEqual(await (await post('/cog/fix', job(), url)).json(), FIX);
    assert.equal(seen.length, at + 1, 'asked once: JSON Schema was not tried first');
    assert.deepEqual(seen.at(-1).body.response_format, { type: 'json_object' });
    assert.equal(seen.at(-1).body.max_tokens, 6000);
    await events(await post('/cog/chat', job(), url));
    assert.equal(seen.at(-1).body.max_tokens, 1500);
  } finally {
    s.close();
  }
  const none = await start({ ...ENV(), COG_JSON_MODE: 'none' });
  try {
    assert.deepEqual(await (await post('/cog/check', job(), `http://127.0.0.1:${none.address().port}`)).json(), CHECK);
    assert.equal(seen.at(-1).body.response_format, undefined);
    assert.equal(seen.at(-1).body.max_tokens, 12000);
  } finally {
    none.close();
  }
});

test('the free Cloudflare set-up (wrangler.jsonc, env.cloudflare) makes a Cog that says who answers', async () => {
  // wrangler.jsonc has comments; strings (which hold // in addresses) are kept as they are.
  const text = fs.readFileSync(new URL('../../cog-worker/wrangler.jsonc', import.meta.url), 'utf8')
    .replace(/("(?:[^"\\]|\\.)*")|\/\/[^\n]*/g, (m, s) => s ?? '');
  const config = JSON.parse(text);
  assert.equal(config.env.cloudflare.name, config.name, 'the same Worker, with another engine');
  const vars = config.env.cloudflare.vars;
  for (const k of Object.keys(config.vars)) if (k !== 'COG_MODEL') assert.equal(vars[k], config.vars[k], `${k} is the same with either engine`);
  // The secrets deploy.sh sets, with the fake service in place of the account's AI address.
  const env = { ...vars, COG_BASE_URL: `${apiBase}/client/v4/accounts/0123456789abcdef0123456789abcdef/ai/v1`, COG_API_KEY: 'cf-token', COG_KEYS: 'school-1' };
  const cfg = cogConfig(env);
  assert.equal(cfg.ready, true, cfg.missing.join(', '));
  const by = 'Llama 3.3, run by Cloudflare|Cloudflare|the United States|hosted';
  const call = (path, body) => worker.fetch(new Request(`https://robocore-cog.example.workers.dev${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json', 'X-Cog-Key': 'school-1' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  }), env, { waitUntil() {} });
  const health = await (await call('/health')).json();
  assert.deepEqual(health.cog, { ready: true, model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast', keys: true, by: { label: 'Llama 3.3, run by Cloudflare', company: 'Cloudflare', where: 'the United States', local: false } });
  assert.equal(said(await events(await call('/cog/chat', job({ by })))), 'Names in Arduino are case-sensitive.');
  const q = seen.at(-1);
  assert.equal(q.path, '/client/v4/accounts/0123456789abcdef0123456789abcdef/ai/v1/chat/completions');
  assert.equal(q.headers.authorization, 'Bearer cf-token');
  assert.equal(q.body.model, '@cf/meta/llama-3.3-70b-instruct-fp8-fast');
  assert.equal(q.body.max_tokens, 1500);
  assert.deepEqual(await (await call('/cog/fix', job({ by }))).json(), FIX);
  assert.deepEqual(seen.at(-1).body.response_format, { type: 'json_object' });
});

test('the Cloudflare Worker runs the same engine', async () => {
  const env = { ...ENV(), COG_LOCAL: '', COG_API_KEY: 'sk-test', COG_AI_NAME: 'DeepSeek', COG_AI_COMPANY: 'DeepSeek', COG_AI_WHERE: 'China' };
  const call = (path, init) => worker.fetch(new Request(`https://cog.example${path}`, init), env, { waitUntil() {} });
  const health = await (await call('/health')).json();
  assert.deepEqual(health.cog.by, { label: 'DeepSeek', company: 'DeepSeek', where: 'China', local: false });
  const r = await call('/cog/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(job({ by: 'DeepSeek|DeepSeek|China|hosted' })) });
  assert.equal(said(await events(r)), 'Names in Arduino are case-sensitive.');
  assert.equal(seen.at(-1).headers.authorization, 'Bearer sk-test');
  const fix = await call('/cog/fix', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(job({ by: 'DeepSeek|DeepSeek|China|hosted' })) });
  assert.deepEqual(await fix.json(), FIX);
  const old = await call('/cog/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(job({ by: undefined })) });
  assert.equal(old.status, 409);
});
