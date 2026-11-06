// Cog on Cloudflare Workers: the same Cog as the RoboCore server (server/src/cog.js: its instructions, the school-key
// check, the calls to the Anthropic API) without the compiler, so the API key never sits next to students' builds.
// The IDE uses this address as its RoboCore server; the routes and answers are the server's:
//
//   GET  /health      {ok, cog: {ready, model, keys}}
//   GET  /cog/key     200 when X-Cog-Key is a school key (the IDE's Test Cog)
//   POST /cog/chat    server-sent events      POST /cog/fix, /cog/check    JSON
//
// Any other request goes to COMPILE_SERVER when it is set (so the web IDE can compile through the same address), or
// answers 404. Settings: ANTHROPIC_API_KEY and COG_KEYS are secrets (`wrangler secret put`); COG_MODEL, COG_EFFORT,
// COG_FIX_EFFORT, COG_RATE_PER_MIN (per address), COG_KEY_RATE_PER_MIN (per school key), ALLOWED_ORIGINS and
// COMPILE_SERVER are in wrangler.jsonc. README.md says how to put it online.
import { cogConfig, makeCog, validateCog } from '../../server/src/cog.js';
import { RequestError } from '../../server/src/errors.js';

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
    const cfg = { ...cogConfig(env), apiKey: env.ANTHROPIC_API_KEY || undefined };
    s = {
      cog: makeCog(cfg),
      allowed: originMatcher(String(env.ALLOWED_ORIGINS || DEFAULT_ORIGINS).split(',').map((o) => o.trim()).filter(Boolean)),
      perAddress: makeLimiter(cfg.ratePerMin),
      perSchool: makeLimiter(Number(env.COG_KEY_RATE_PER_MIN || 60)),
      compile: String(env.COMPILE_SERVER || '').replace(/\/+$/, ''),
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

const tooMany = (cors, message) => json(429, { error: message }, { ...cors, 'Retry-After': '60' });

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
          headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, X-Cog-Key', 'Access-Control-Max-Age': '600' },
        });
      }
      if (request.method === 'GET' && url.pathname === '/health') {
        return json(200, { ok: true, cog: { ready: s.cog.ready, model: s.cog.model, keys: s.cog.keys }, compile: Boolean(s.compile) }, cors);
      }
      if (url.pathname === '/cog/key' || url.pathname.startsWith('/cog/')) {
        if (origin && !cors['Access-Control-Allow-Origin']) return json(403, { error: 'Origin not allowed.' }, cors);
        // Cloudflare sets CF-Connecting-IP itself, so a client can't claim another address to dodge the limit.
        const ip = request.headers.get('CF-Connecting-IP') || '?';
        // The limit comes first, so keys can't be guessed quickly.
        if (!s.perAddress(ip)) return tooMany(cors, 'Cog needs a short break. Wait a minute and ask again.');
        const key = request.headers.get('X-Cog-Key') ?? undefined;
        s.cog.admit(key);
        if (request.method === 'GET' && url.pathname === '/cog/key') return json(200, { ok: true }, cors);
        const kind = url.pathname.slice(5);
        if (request.method !== 'POST' || !['chat', 'fix', 'check'].includes(kind)) return json(404, { error: 'Not found.' }, cors);
        // A whole school shares one key: this caps what it can spend, however many addresses it asks from.
        if (!s.perSchool(key ?? '')) return tooMany(cors, 'Cog is busy for your school right now. Wait a minute and ask again.');
        const job = validateCog(await readJson(request), { needTask: kind === 'chat' });
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
