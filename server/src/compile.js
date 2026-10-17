// Validates a compile request, runs arduino-cli in a throwaway folder and collects the program image.
import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, readFile, rm, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { BOARDS, ESP32_PARTS } from './boards.js';
import { parseCliJson, parseDiagnostics, parseStructured, mergeProblems, parseSizes, scrub } from './parse.js';

export const LIMITS = {
  maxFiles: 20,
  maxFileBytes: 200_000,
  maxTotalBytes: 400_000,
};

const NAME = /^[A-Za-z][A-Za-z0-9_-]{0,63}\.(ino|h|hpp|c|cpp)$/;

export class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// Checks the JSON body. Returns { boardId, board, files, main }.
export function validateRequest(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new RequestError(400, 'Send a JSON object.');
  const boardId = body.board;
  if (typeof boardId !== 'string' || !Object.hasOwn(BOARDS, boardId)) {
    throw new RequestError(400, `Unknown board. Use one of: ${Object.keys(BOARDS).join(', ')}.`);
  }
  const files = body.files;
  if (!Array.isArray(files) || files.length === 0) throw new RequestError(400, 'Send at least one file.');
  if (files.length > LIMITS.maxFiles) throw new RequestError(400, `A sketch can have at most ${LIMITS.maxFiles} files.`);
  const seen = new Set();
  let total = 0;
  const clean = [];
  for (const f of files) {
    if (!f || typeof f.name !== 'string' || typeof f.content !== 'string') throw new RequestError(400, 'Each file needs a name and content.');
    if (!NAME.test(f.name)) {
      throw new RequestError(400, `"${String(f.name).slice(0, 80)}" is not an allowed file name. Use letters, numbers, _ or - and end in .ino, .h, .hpp, .c or .cpp.`);
    }
    const key = f.name.toLowerCase();
    if (seen.has(key)) throw new RequestError(400, `Two files are called ${f.name}.`);
    seen.add(key);
    const bytes = Buffer.byteLength(f.content, 'utf8');
    if (bytes > LIMITS.maxFileBytes) throw new RequestError(413, `${f.name} is too big (over ${LIMITS.maxFileBytes / 1000} KB).`);
    total += bytes;
    clean.push({ name: f.name, content: f.content });
  }
  if (total > LIMITS.maxTotalBytes) throw new RequestError(413, 'The sketch is too big.');
  const inos = clean.filter((f) => f.name.endsWith('.ino'));
  if (inos.length === 0) throw new RequestError(400, 'A sketch needs one .ino file.');
  let main = inos[0].name;
  if (typeof body.main === 'string') {
    if (!inos.some((f) => f.name === body.main)) throw new RequestError(400, `${String(body.main).slice(0, 80)} is not one of the .ino files.`);
    main = body.main;
  }
  return { boardId, board: BOARDS[boardId], files: clean, main };
}

let bootApp0Cache = null;
async function findBootApp0(cfg) {
  if (cfg.bootApp0) return cfg.bootApp0;
  if (bootApp0Cache) return bootApp0Cache;
  const base = path.join(cfg.dataDir, 'packages', 'esp32', 'hardware', 'esp32');
  const versions = (await readdir(base)).sort().reverse();
  for (const v of versions) {
    const p = path.join(base, v, 'tools', 'partitions', 'boot_app0.bin');
    try {
      await readFile(p);
      bootApp0Cache = p;
      return p;
    } catch { /* try the next version */ }
  }
  throw new Error('boot_app0.bin not found in the esp32 core');
}

function run(cmd, args, opts) {
  return new Promise((resolve) => {
    execFile(cmd, args, opts, (err, stdout, stderr) => {
      resolve({ err, stdout: String(stdout ?? ''), stderr: String(stderr ?? '') });
    });
  });
}

// Environment for arduino-cli: only what it needs, so no server settings leak into builds.
function cliEnv(cfg) {
  const env = { PATH: process.env.PATH ?? '/usr/local/bin:/usr/bin:/bin', HOME: cfg.home, LANG: 'C.UTF-8' };
  for (const [k, v] of Object.entries(process.env)) {
    if (k.startsWith('ARDUINO_')) env[k] = v;
  }
  return env;
}

// Compiles a validated request. Resolves to the JSON body for the IDE.
export async function compileSketch(req, cfg) {
  const started = Date.now();
  const work = await mkdtemp(path.join(cfg.tmpDir ?? os.tmpdir(), 'rc-'));
  const sketchName = req.main.replace(/\.ino$/, '');
  const sketchDir = path.join(work, sketchName);
  const buildDir = path.join(work, 'build');
  const scrubPaths = [
    [sketchDir + path.sep, ''],
    [sketchDir, sketchName],
    [buildDir, '<build>'],
    [work, ''],
    [cfg.libraryDir, '<RoboCore>'],
    [cfg.dataDir, '<arduino>'],
    [cfg.home, '~'],
  ];
  try {
    await mkdir(sketchDir, { recursive: true });
    await mkdir(buildDir, { recursive: true });
    for (const f of req.files) await writeFile(path.join(sketchDir, f.name), f.content, 'utf8');

    const args = [
      'compile',
      '--fqbn', req.board.fqbn,
      '--build-path', buildDir,
      '--library', cfg.libraryDir,
      '--warnings', 'default',
      '--jobs', String(cfg.jobs ?? 0),
      '--format', 'json',
      sketchDir,
    ];
    const r = await run(cfg.cli, args, {
      cwd: work,
      env: cliEnv(cfg),
      timeout: cfg.timeoutMs,
      killSignal: 'SIGKILL',
      maxBuffer: 32 * 1024 * 1024,
    });
    if (r.err && (r.err.killed || r.err.signal === 'SIGKILL')) {
      throw new RequestError(504, `Compiling took longer than ${Math.round(cfg.timeoutMs / 1000)} seconds and was stopped.`);
    }
    const result = parseCliJson(r.stdout);
    if (!result) {
      const detail = scrub((r.stderr || r.stdout).slice(-2000), scrubPaths).trim();
      throw Object.assign(new Error(`arduino-cli gave no result${detail ? `: ${detail}` : ''}`), { status: 500 });
    }
    const compilerOut = scrub(result.compiler_out, scrubPaths);
    const compilerErr = scrub(result.compiler_err, scrubPaths);
    const names = req.files.map((f) => f.name);
    let problems = mergeProblems(
      parseStructured(result.builder_result?.diagnostics, sketchDir, names).map((p) => ({ ...p, message: scrub(p.message, scrubPaths), ...(p.source ? { source: scrub(p.source, scrubPaths) } : {}) })),
      parseDiagnostics(`${compilerErr}\n${compilerOut}`, '', names),
    );
    problems.sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'error' ? -1 : 1));
    const log = `${compilerOut}${compilerErr ? `\n${compilerErr}` : ''}`.trim();
    const elapsedMs = Date.now() - started;

    if (!result.success) {
      if (!problems.some((p) => p.severity === 'error')) {
        problems = [{ severity: 'error', file: req.main, line: 1, column: null, message: scrub(result.error || 'Compilation failed.', scrubPaths) }, ...problems];
      }
      return { ok: false, board: req.boardId, problems, log, elapsedMs };
    }

    const sizes = parseSizes(result, compilerOut);
    let image;
    if (req.board.arch === 'esp32') {
      const files = {
        bootloader: path.join(buildDir, `${req.main}.bootloader.bin`),
        partitions: path.join(buildDir, `${req.main}.partitions.bin`),
        boot_app0: await findBootApp0(cfg),
        app: path.join(buildDir, `${req.main}.bin`),
      };
      const parts = [];
      for (const part of ESP32_PARTS(req.board)) {
        const data = await readFile(files[part.file]);
        parts.push({ name: part.file, offset: part.offset, size: data.length, data: data.toString('base64') });
      }
      image = { format: 'esp32', chip: req.board.chip, flashSize: req.board.flashSize, parts };
    } else {
      const hex = await readFile(path.join(buildDir, `${req.main}.hex`), 'utf8');
      image = { format: 'hex', data: hex };
    }
    return { ok: true, board: req.boardId, problems, sizes, log, image, elapsedMs };
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}
