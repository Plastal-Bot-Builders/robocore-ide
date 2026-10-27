// RoboCore compile server.
//   POST /compile  { board, files: [{ name, content }], main? }  ->  { ok, problems, sizes, log, image }
//   GET  /health   GET /boards
// No outside packages: only Node's own http, child_process and fs.
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { BOARDS } from './boards.js';
import { validateRequest, compileSketch, RequestError, LIMITS } from './compile.js';
import { cogConfig, makeCog, validateCog } from './cog.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const env = process.env;

export function loadConfig(over = {}) {
  const home = env.HOME || os.homedir();
  return {
    port: Number(env.PORT || 8080),
    cli: env.ARDUINO_CLI || 'arduino-cli',
    libraryDir: path.resolve(env.ROBOCORE_LIBRARY || path.join(here, '..', '..', 'firmware', 'RoboCore')),
    // arduino-cli's default data folder: ~/Library/Arduino15 on macOS, ~/.arduino15 on Linux.
    dataDir: env.ARDUINO_DIRECTORIES_DATA
      || (process.platform === 'darwin' ? path.join(home, 'Library', 'Arduino15') : path.join(home, '.arduino15')),
    home,
    bootApp0: env.BOOT_APP0 || null,
    tmpDir: env.COMPILE_TMP || os.tmpdir(),
    timeoutMs: Number(env.COMPILE_TIMEOUT_MS || 120_000),
    jobs: Number(env.COMPILE_JOBS || 2),
    maxRunning: Number(env.MAX_RUNNING || 1),
    maxQueued: Number(env.MAX_QUEUED || 8),
    ratePerMin: Number(env.RATE_PER_MIN || 20),
    allowedOrigins: (env.ALLOWED_ORIGINS || 'https://plastal-bot-builders.github.io,http://localhost:*,http://127.0.0.1:*')
      .split(',').map((s) => s.trim()).filter(Boolean),
    bodyLimit: 1_000_000,
    cog: cogConfig(env),
    ...over,
  };
}

// ---------- CORS ----------
function originMatcher(list) {
  const res = list.map((o) => {
    if (o === '*') return /^.*$/;
    const esc = o.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/:\\\*$/, '(:\\d+)?').replace(/:\*$/, '(:\\d+)?');
    return new RegExp(`^${esc}$`);
  });
  return (origin) => !!origin && res.some((r) => r.test(origin));
}

// ---------- queue: a few compiles at a time, the rest wait ----------
function makeQueue(maxRunning, maxQueued) {
  let running = 0;
  const waiting = [];
  const next = () => {
    if (running >= maxRunning || waiting.length === 0) return;
    running++;
    const { job, resolve, reject } = waiting.shift();
    job().then(resolve, reject).finally(() => {
      running--;
      next();
    });
  };
  return {
    get running() { return running; },
    get queued() { return waiting.length; },
    push(job) {
      if (waiting.length >= maxQueued) return null;
      return new Promise((resolve, reject) => {
        waiting.push({ job, resolve, reject });
        next();
      });
    },
  };
}

// ---------- rate limit per client ----------
function makeLimiter(perMin) {
  const hits = new Map();
  setInterval(() => {
    const cut = Date.now() - 60_000;
    for (const [k, v] of hits) if (v.start < cut) hits.delete(k);
  }, 60_000).unref();
  return (key) => {
    const now = Date.now();
    const h = hits.get(key);
    if (!h || now - h.start >= 60_000) {
      hits.set(key, { start: now, n: 1 });
      return true;
    }
    h.n++;
    return h.n <= perMin;
  };
}

function send(res, status, body, extra = {}) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(data),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...extra,
  });
  res.end(data);
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(new RequestError(413, 'Request too big.'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function toolVersions(cfg) {
  return new Promise((resolve) => {
    execFile(cfg.cli, ['version', '--format', 'json'], { timeout: 10_000, env: { PATH: process.env.PATH, HOME: cfg.home } }, (err, out) => {
      let cli = null;
      try { cli = JSON.parse(out).VersionString ?? null; } catch { /* unknown */ }
      execFile(cfg.cli, ['core', 'list', '--format', 'json'], { timeout: 20_000, env: { PATH: process.env.PATH, HOME: cfg.home } }, (err2, out2) => {
        let cores = [];
        try {
          const j = JSON.parse(out2);
          const list = Array.isArray(j) ? j : (j.platforms ?? []);
          cores = list.map((p) => `${p.id ?? p.metadata?.id}@${p.installed ?? p.installed_version ?? ''}`);
        } catch { /* unknown */ }
        resolve({ arduinoCli: cli, cores });
      });
    });
  });
}

export function createServer(cfg = loadConfig()) {
  const allowed = originMatcher(cfg.allowedOrigins);
  const queue = makeQueue(cfg.maxRunning, cfg.maxQueued);
  const limit = makeLimiter(cfg.ratePerMin);
  const cog = makeCog(cfg.cog);
  const cogLimit = makeLimiter(cfg.cog.ratePerMin);
  let versions = { arduinoCli: null, cores: [] };
  toolVersions(cfg).then((v) => { versions = v; });

  const server = http.createServer(async (req, res) => {
    const origin = req.headers.origin;
    const cors = {};
    if (origin && allowed(origin)) {
      cors['Access-Control-Allow-Origin'] = origin;
      cors.Vary = 'Origin';
    }
    const url = new URL(req.url, 'http://x');
    const t0 = Date.now();
    res.on('finish', () => {
      if (url.pathname !== '/health') console.log(`${req.method} ${url.pathname} ${res.statusCode} ${Date.now() - t0}ms`);
    });
    try {
      if (req.method === 'OPTIONS') {
        if (!cors['Access-Control-Allow-Origin']) return send(res, 403, { error: 'Origin not allowed.' });
        res.writeHead(204, {
          ...cors,
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, X-Cog-Key',
          'Access-Control-Max-Age': '600',
        });
        return res.end();
      }
      if (req.method === 'GET' && url.pathname === '/health') {
        return send(res, 200, { ok: true, ...versions, running: queue.running, queued: queue.queued, cog: { ready: cog.ready, model: cog.model, keys: cog.keys } }, cors);
      }
      if (req.method === 'GET' && url.pathname === '/boards') {
        return send(res, 200, { boards: Object.entries(BOARDS).map(([id, b]) => ({ id, name: b.name, fqbn: b.fqbn, arch: b.arch })), limits: LIMITS }, cors);
      }
      if (req.method === 'POST' && url.pathname === '/compile') {
        if (origin && !cors['Access-Control-Allow-Origin']) return send(res, 403, { error: 'Origin not allowed.' });
        const ip = String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim() || req.socket.remoteAddress || '?';
        if (!limit(ip)) return send(res, 429, { error: 'Too many compiles. Wait a minute and try again.' }, { ...cors, 'Retry-After': '60' });
        if (!String(req.headers['content-type'] ?? '').includes('application/json')) {
          throw new RequestError(415, 'Send JSON (Content-Type: application/json).');
        }
        let body;
        try {
          body = JSON.parse(await readBody(req, cfg.bodyLimit));
        } catch (e) {
          if (e instanceof RequestError) throw e;
          throw new RequestError(400, 'The request is not valid JSON.');
        }
        const job = validateRequest(body);
        const pending = queue.push(() => compileSketch(job, cfg));
        if (!pending) return send(res, 503, { error: 'The compile server is busy. Try again in a few seconds.' }, { ...cors, 'Retry-After': '5' });
        const result = await pending;
        return send(res, 200, result, cors);
      }
      if (req.method === 'GET' && url.pathname === '/cog/key') {
        const ip = String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim() || req.socket.remoteAddress || '?';
        if (!cogLimit(ip)) return send(res, 429, { error: 'Cog needs a short break. Wait a minute and ask again.' }, { ...cors, 'Retry-After': '60' });
        cog.admit(req.headers['x-cog-key']);
        return send(res, 200, { ok: true }, cors);
      }
      if (req.method === 'POST' && url.pathname.startsWith('/cog/')) {
        const kind = url.pathname.slice(5);
        if (!['chat', 'fix', 'check'].includes(kind)) return send(res, 404, { error: 'Not found.' }, cors);
        if (origin && !cors['Access-Control-Allow-Origin']) return send(res, 403, { error: 'Origin not allowed.' });
        const ip = String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim() || req.socket.remoteAddress || '?';
        // The limit comes first, so keys can't be guessed quickly.
        if (!cogLimit(ip)) return send(res, 429, { error: 'Cog needs a short break. Wait a minute and ask again.' }, { ...cors, 'Retry-After': '60' });
        cog.admit(req.headers['x-cog-key']);
        if (!String(req.headers['content-type'] ?? '').includes('application/json')) {
          throw new RequestError(415, 'Send JSON (Content-Type: application/json).');
        }
        let body;
        try {
          body = JSON.parse(await readBody(req, cfg.bodyLimit));
        } catch (e) {
          if (e instanceof RequestError) throw e;
          throw new RequestError(400, 'The request is not valid JSON.');
        }
        const job = validateCog(body, { needTask: kind === 'chat' });
        if (kind === 'chat') {
          return await cog.chat(job, res, cors, (stop) => res.on('close', () => { if (!res.writableEnded) stop(); }));
        }
        return send(res, 200, kind === 'fix' ? await cog.fix(job) : await cog.check(job), cors);
      }
      return send(res, 404, { error: 'Not found.' }, cors);
    } catch (e) {
      const status = e.status ?? 500;
      if (!(e instanceof RequestError)) console.error(e);
      return send(res, status, { error: status >= 500 && !(e instanceof RequestError) ? 'The compile server hit a problem. Try again.' : e.message }, cors);
    }
  });
  server.requestTimeout = cfg.timeoutMs + 30_000;
  return server;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const cfg = loadConfig();
  const server = createServer(cfg);
  server.listen(cfg.port, () => console.log(`RoboCore compile server on :${cfg.port} (library ${cfg.libraryDir})`));
  const stop = () => server.close(() => process.exit(0));
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
}
