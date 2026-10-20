// Turns arduino-cli output into what the IDE shows: problems with file and line, sizes, a tidy log.

const DIAG = /^(.*?):(\d+):(?:(\d+):)?\s*(fatal error|error|warning|note):\s*(.*)$/;
const LINK = /undefined reference to [`'"]?([^`'"]+)[`'"]?/;

// Hide server paths from anything sent back to the browser:
// first the exact folders this build used, then any Arduino install, home folder or temp folder.
const GENERIC = [
  [/(?:[A-Za-z]:)?[/\\][^\s'"`:]*?[/\\]\.arduino15(?=[/\\])/g, '<arduino>'],
  [/(?:[A-Za-z]:)?[/\\][^\s'"`:]*?[/\\]rc-[A-Za-z0-9]{6,}(?=[/\\]|\b)/g, ''],
  [/\/(?:home|Users)\/[^/\s'"`:]+/g, '~'],
  [/\/root(?=\/)/g, '~'],
];
export function scrub(text, paths) {
  let out = String(text ?? '');
  for (const [from, to] of paths) {
    if (from) out = out.split(from).join(to);
  }
  for (const [re, to] of GENERIC) out = out.replace(re, to);
  return out;
}

// Problems from compiler/linker output. `sketchFiles` are the user's file names.
export function parseDiagnostics(text, sketchDir, sketchFiles) {
  const problems = [];
  const seen = new Set();
  const names = new Set(sketchFiles);
  for (const raw of String(text ?? '').split(/\r?\n/)) {
    const line = raw.trimEnd();
    let m = DIAG.exec(line);
    if (m) {
      const [, path, ln, col, sev, msg] = m;
      if (sev === 'note') continue;
      let file = null;
      if (sketchDir && path.startsWith(sketchDir)) file = path.slice(sketchDir.length).replace(/^[/\\]+/, '');
      else {
        const base = path.split(/[/\\]/).pop();
        if (names.has(base)) file = base;
      }
      const p = {
        severity: sev === 'warning' ? 'warning' : 'error',
        file: file ?? 'library',
        line: Number(ln),
        column: col ? Number(col) : null,
        message: msg.trim(),
      };
      if (!file) p.source = path.split(/[/\\]/).slice(-2).join('/');
      const key = `${p.severity}|${p.file}|${p.line}|${p.message}`;
      if (!seen.has(key)) {
        seen.add(key);
        problems.push(p);
      }
      continue;
    }
    m = LINK.exec(line);
    if (m) {
      const sym = m[1].trim();
      const key = `link|${sym}`;
      if (!seen.has(key)) {
        seen.add(key);
        const friendly = sym === 'setup()' || sym === 'loop()' || sym === 'setup' || sym === 'loop'
          ? `Every sketch needs a ${sym.replace('()', '')}() function.`
          : `${sym} is used but never defined (missing function body or library?).`;
        problems.push({ severity: 'error', file: sketchFiles[0] ?? null, line: 1, column: null, message: `undefined reference to '${sym}'. ${friendly}` });
      }
    }
  }
  return problems;
}

// Problems from arduino-cli's structured builder_result.diagnostics (preferred when present).
export function parseStructured(diags, sketchDir, sketchFiles) {
  if (!Array.isArray(diags)) return [];
  const names = new Set(sketchFiles);
  const out = [];
  for (const d of diags) {
    const sev = String(d?.severity ?? '').toLowerCase();
    if (sev.includes('note')) continue;
    const path = String(d?.file ?? '');
    let file = null;
    if (sketchDir && path.startsWith(sketchDir)) file = path.slice(sketchDir.length).replace(/^[/\\]+/, '');
    else if (names.has(path.split(/[/\\]/).pop())) file = path.split(/[/\\]/).pop();
    const p = {
      severity: sev.includes('warn') ? 'warning' : 'error',
      file: file ?? 'library',
      line: Number(d?.line) || 1,
      column: Number(d?.column) || null,
      message: String(d?.message ?? '').trim(),
    };
    if (!file && path) p.source = path.split(/[/\\]/).slice(-2).join('/');
    if (p.message) out.push(p);
  }
  return out;
}

// Merge two problem lists without repeats.
export function mergeProblems(a, b) {
  const seen = new Set();
  const out = [];
  for (const p of [...a, ...b]) {
    // The text log repeats a diagnostic with the code excerpt under it: compare first lines only.
    const key = `${p.severity}|${p.file}|${p.line}|${String(p.message).split('\n')[0].trim()}`;
    if (!seen.has(key)) {
      seen.add(key);
      out.push(p);
    }
  }
  return out;
}

// Program and RAM use, from arduino-cli's JSON builder_result or the text summary.
export function parseSizes(result, compilerOut) {
  const sections = result?.builder_result?.executable_sections_size;
  const sizes = {};
  if (Array.isArray(sections)) {
    for (const s of sections) {
      if (s?.name === 'text') sizes.flash = { used: s.size, max: s.max_size };
      if (s?.name === 'data') sizes.ram = { used: s.size, max: s.max_size };
    }
  }
  const out = String(compilerOut ?? '');
  if (!sizes.flash) {
    const m = /Sketch uses (\d+) bytes .*?Maximum is (\d+) bytes/.exec(out);
    if (m) sizes.flash = { used: Number(m[1]), max: Number(m[2]) };
  }
  if (!sizes.ram) {
    const m = /Global variables use (\d+) bytes .*?Maximum is (\d+) bytes/.exec(out);
    if (m) sizes.ram = { used: Number(m[1]), max: Number(m[2]) };
  }
  return sizes;
}

// arduino-cli --json output can be preceded by other text; take the last JSON object.
export function parseCliJson(stdout) {
  const s = String(stdout ?? '').trim();
  try {
    return JSON.parse(s);
  } catch {
    const i = s.lastIndexOf('\n{');
    if (i >= 0) {
      try {
        return JSON.parse(s.slice(i + 1));
      } catch { /* fall through */ }
    }
    const j = s.indexOf('{');
    if (j >= 0) {
      try {
        return JSON.parse(s.slice(j));
      } catch { /* fall through */ }
    }
  }
  return null;
}
