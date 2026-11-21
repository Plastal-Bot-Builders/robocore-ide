// Cog on Cloudflare Workers: the same Cog as the RoboCore server (server/src/cog.js: its instructions, the school-key
// check, the calls to the Anthropic API) without the compiler, so the API key never sits next to students' builds.
// The IDE uses this address as its RoboCore server; the routes and answers are the server's:
//
//   GET  /health      {ok, cog: {ready, model, keys, by}}
//   GET  /cog/key     200 when X-Cog-Key is a school key (the IDE's Test Cog)
//   POST /cog/chat    server-sent events      POST /cog/fix, /cog/check    JSON
//
// Any other request goes to COMPILE_SERVER when it is set (so the web IDE can compile through the same address), or
// answers 404. Settings: ANTHROPIC_API_KEY and COG_KEYS are secrets (`wrangler secret put`); COG_MODEL, COG_EFFORT,
// COG_FIX_EFFORT, COG_RATE_PER_MIN (per address), COG_KEY_RATE_PER_MIN (per school key), ALLOWED_ORIGINS and
// COMPILE_SERVER are in wrangler.jsonc. README.md says how to put it online.
//
// Open to everyone (COG_OPEN=1, so the IDE needs no school key): then each computer, each internet address and everyone
// together get a number of questions a day (COG_DEVICE_DAY_LIMIT, COG_ADDRESS_DAY_LIMIT, COG_DAY_LIMIT), counted by
// the QUOTA Durable Object (src/quota.js). A school key still works and skips those daily limits.
import { cogConfig, makeCog, validateCog } from '../../server/src/cog.js';
import { RequestError } from '../../server/src/errors.js';
import { CogQuota, hashFor, secondsToTomorrow, today } from './quota.js';

export { CogQuota };

const BODY_LIMIT = 1_000_000;
const DEFAULT_ORIGINS = 'https://plastal-bot-builders.github.io,http://localhost:*,http://127.0.0.1:*';

// As in the server: an origin, or one ending in :* for any port. The desktop apps send no Origin and are let in.
function originMatcher(list) {
  const res = list.map((o) => {
    if (o === '*') return /^.*$/;
    const esc = o.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/:\\\*$/, '(:\\d+)?').replace(/:\*$/, '(:\\d+)?');
    return new RegExp(`^${esc}$`);
  });
  return (origin) => !!origin && res.some((r) => r.test(origin));
}

// Requests per minute per key. Each Worker instance counts on its own, so the limit holds per instance: enough to
// stop one client running away with the credit, not an exact count.
function makeLimiter(perMin) {
  const hits = new Map();
  return (key) => {
    const now = Date.now();
    if (hits.size > 10_000) for (const [k, v] of hits) if (now - v.start >= 60_000) hits.delete(k);
    const h = hits.get(key);
    if (!h || now - h.start >= 60_000) {
      hits.set(key, { start: now, n: 1 });
      return true;
    }
    h.n++;
    return h.n <= perMin;
  };
}

// One Cog per set of settings; an instance keeps the same env from request to request.
const setups = new WeakMap();
function setup(env) {
  let s = setups.get(env);
  if (!s) {
    const cfg = cogConfig(env); // it carries the key: a Worker has no process.env for the SDK to read
    s = {
      cog: makeCog(cfg),
      allowed: originMatcher(String(env.ALLOWED_ORIGINS || DEFAULT_ORIGINS).split(',').map((o) => o.trim()).filter(Boolean)),
      perAddress: makeLimiter(cfg.ratePerMin),
      perSchool: makeLimiter(Number(env.COG_KEY_RATE_PER_MIN || 60)),
      compile: String(env.COMPILE_SERVER || '').replace(/\/+$/, ''),
      open: cfg.open,
      day: {
        all: Number(env.COG_DAY_LIMIT || 45),
        device: Number(env.COG_DEVICE_DAY_LIMIT || 15),
        address: Number(env.COG_ADDRESS_DAY_LIMIT || 40),
      },
    };
    setups.set(env, s);
  }
  return s;
}

const json = (status, body, headers = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' },
  });

const tooMany = (cors, message, retryAfter = 60) => json(429, { error: message }, { ...cors, 'Retry-After': String(retryAfter) });

const DEVICE = /^[A-Za-z0-9-]{8,64}$/;
const DAY_DONE = {
  all: 'Cog has answered all the questions it can for today. It will be back tomorrow.',
  device: 'Cog has answered all the questions it can on this computer today. It will be back tomorrow.',
  address: 'Cog has answered all the questions it can for this internet connection today. It will be back tomorrow.',
};

// One question against the daily limits of an open Cog. Null when it may go ahead, otherwise what to tell the student.
// The device is the IDE's own random number (X-Cog-Device); an IDE that sends none counts by its address.
async function daily(env, s, request, ip) {
  if (!env.QUOTA) throw new RequestError(503, 'Cog is open to everyone here, but its daily limits are not set up yet (the QUOTA Durable Object).');
  const day = today();
  const raw = String(request.headers.get('X-Cog-Device') ?? '');
  const body = {
    day,
    device: await hashFor(day, 'device', DEVICE.test(raw) ? raw : `address:${ip}`),
    address: await hashFor(day, 'address', ip),
    limits: s.day,
  };
  const stub = env.QUOTA.get(env.QUOTA.idFromName('cog'));
  const r = await (await stub.fetch('https://quota/take', { method: 'POST', body: JSON.stringify(body) })).json();
  return r.ok ? null : DAY_DONE[r.why] ?? DAY_DONE.all;
}

async function readJson(request) {
  if (!String(request.headers.get('Content-Type') ?? '').includes('application/json')) {
    throw new RequestError(415, 'Send JSON (Content-Type: application/json).');
  }
  if (Number(request.headers.get('Content-Length') ?? 0) > BODY_LIMIT) throw new RequestError(413, 'The request is too big.');
  const text = await request.text();
  if (text.length > BODY_LIMIT) throw new RequestError(413, 'The request is too big.');
  try {
    return JSON.parse(text);
  } catch {
    throw new RequestError(400, 'The request is not valid JSON.');
  }
}

// cog.chat() writes to a Node response; this one passes what it writes on as the body of a streamed Response. If the
// IDE goes away, the next write fails and the request to the API is stopped.
async function chat(cog, job, cors, ctx) {
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  const enc = new TextEncoder();
  let stop = null;
  let gone = false;
  let opened;
  const head = new Promise((resolve) => {
    opened = resolve;
  });
  const res = {
    writableEnded: false,
    writeHead(status, headers) {
      opened({ status, headers });
    },
    write(s) {
      writer.write(enc.encode(s)).catch(() => {
        if (!gone) {
          gone = true;
          stop?.();
        }
      });
    },
    end() {
      this.writableEnded = true;
      writer.close().catch(() => {});
    },
  };
  const done = cog.chat(job, res, cors, (fn) => {
    stop = fn;
  });
  ctx?.waitUntil?.(done.catch(() => {}));
  // Before it starts streaming, cog.chat can still fail with a RequestError (no API key): that is answered as JSON.
  const first = await Promise.race([head, done.then(() => null)]);
  if (!first) throw new RequestError(502, 'Cog hit a problem. Try again.');
  return new Response(readable, { status: first.status, headers: first.headers });
}

async function proxy(request, target, cors) {
  try {
    return await fetch(new Request(target, request));
  } catch {
    return json(502, { error: 'Could not reach the compile server behind this address. Try again in a minute.' }, cors);
  }
}

export default {
  async fetch(request, env = {}, ctx) {
    const s = setup(env);
    const url = new URL(request.url);
    const origin = request.headers.get('Origin');
    const cors = {};
    if (origin && s.allowed(origin)) {
      cors['Access-Control-Allow-Origin'] = origin;
      cors.Vary = 'Origin';
    }
    try {
      if (request.method === 'OPTIONS') {
        if (!cors['Access-Control-Allow-Origin']) return json(403, { error: 'Origin not allowed.' });
        return new Response(null, {
          status: 204,
          headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, X-Cog-Key, X-Cog-Device', 'Access-Control-Max-Age': '600' },
        });
      }
      if (request.method === 'GET' && url.pathname === '/health') {
        return json(200, { ok: true, cog: { ready: s.cog.ready, model: s.cog.model, keys: s.cog.keys, open: s.open, by: s.cog.by }, compile: Boolean(s.compile) }, cors);
      }
      if (url.pathname === '/cog/key' || url.pathname.startsWith('/cog/')) {
        if (origin && !cors['Access-Control-Allow-Origin']) return json(403, { error: 'Origin not allowed.' }, cors);
        // Cloudflare sets CF-Connecting-IP itself, so a client can't claim another address to dodge the limit.
        const ip = request.headers.get('CF-Connecting-IP') || '?';
        // The limit comes first, so keys can't be guessed quickly.
        if (!s.perAddress(ip)) return tooMany(cors, 'Cog needs a short break. Wait a minute and ask again.');
        const key = request.headers.get('X-Cog-Key') ?? undefined;
        s.cog.admit(key); // open: everyone; otherwise a school key
        const school = s.cog.knows(key);
        if (request.method === 'GET' && url.pathname === '/cog/key') return json(200, { ok: true }, cors);
        const kind = url.pathname.slice(5);
        if (request.method !== 'POST' || !['chat', 'fix', 'check'].includes(kind)) return json(404, { error: 'Not found.' }, cors);
        // A whole school shares one key: this caps what it can spend, however many addresses it asks from. Everyone
        // without a key shares one count too.
        if (!s.perSchool(school ? key : '')) {
          return tooMany(cors, school ? 'Cog is busy for your school right now. Wait a minute and ask again.' : 'Cog is busy right now. Wait a minute and ask again.');
        }
        const body = await readJson(request);
        s.cog.agree(body?.by);
        const job = validateCog(body, { needTask: kind === 'chat' });
        // Only a question that is going to the AI is counted.
        if (s.open && !school) {
          const done = await daily(env, s, request, ip);
          if (done) return tooMany(cors, done, secondsToTomorrow());
        }
        if (kind === 'chat') return await chat(s.cog, job, cors, ctx);
        return json(200, kind === 'fix' ? await s.cog.fix(job) : await s.cog.check(job), cors);
      }
      if (s.compile) return await proxy(request, s.compile + url.pathname + url.search, cors);
      return json(404, { error: 'This address runs Cog only. Compile on this computer, or set a compile server.' }, cors);
    } catch (e) {
      const status = e.status ?? 500;
      if (!(e instanceof RequestError)) console.error(e);
      return json(status, { error: status >= 500 && !(e instanceof RequestError) ? 'Cog hit a problem. Try again.' : e.message }, cors);
    }
  },
};
