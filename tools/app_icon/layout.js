#!/usr/bin/env node
// Lays out the RoboCore IDE app icon ("Geared Ring", round 3) on every plate shape and prints
// the path data as JSON. tools/gen_app_icons.py runs this and rasterises the result.
//
// geom.js and concepts.js are copies of RoboCore_IDE_Design/app-icon, the master behind the
// Figma file "RoboCore IDE — App Icon"; copy them again if the master changes. The numbers below
// mirror AI_SHAPES, AI_VERSIONS.orbit and aiIcon() in RoboCore_IDE_Design/icon-plugin/src/12_app_icon.js.
//
// All paths are absolute M/L/C/Z commands on a 1024 × 1024 canvas.
const IG = require('./geom.js');
globalThis.IG = IG;
const { CONCEPTS } = require('./concepts.js');

const GLYPH = CONCEPTS.gearring;
const SCALE = 0.94;  // master glyph on the 824 macOS plate
const EXTENT = 404;  // farthest point of the master glyph from the centre
const ANDROID_FG = 0.7;  // adaptive-icon foreground: inside the 66 dp safe circle

const SHAPES = {
  macOS: { plate: [100, 100, 824, 824], r: 185.4, s: 0.6, shadow: { dy: 10, blur: 20, opacity: 0.28 } },
  Square: { plate: [0, 0, 1024, 1024], r: 0, safe: 450 },
  Rounded: { plate: [0, 0, 1024, 1024], r: 229, s: 0.6, safe: 450 },
  Maskable: { plate: [0, 0, 1024, 1024], r: 0, safe: 0.8 * 512 },
};

// one flat ink on a flat plate
const LOOKS = {
  Default: { plate: '#F2B01E', ink: '#1B2A41' },
  Dark: { plate: '#1B2A41', ink: '#F2B01E' },
  Tinted: { plate: '#1C1C1E', ink: '#FFFFFF' },
};

const glyphPath = (o) => GLYPH.glyph(o).map((l) => l.d).join(' ');
const GLYPHS = { master: glyphPath(), small: glyphPath(GLYPH.small) };

// scale a 1024-canvas path by k about its centre and move the centre to (cx, cy)
function place(d, k, cx, cy) {
  let i = 0;
  return d.replace(/-?\d*\.?\d+(?:e[-+]?\d+)?/g, (n) => IG.f((i++ % 2 ? cy : cx) + (parseFloat(n) - 512) * k));
}

function platePath(S) {
  const [x, y, w, h] = S.plate;
  return S.r ? IG.squircle(x, y, w, h, S.r, S.s) : IG.rrect(x, y, w, h, 0);
}

// the master is drawn for the 824 plate, the small glyph (16–32 px) for a full canvas
function glyphScale(S, fit) {
  const pw = S.plate[2];
  if (fit === 'small') return pw / 1024;
  const k = (pw / 824) * SCALE;
  return S.safe ? Math.min(k, S.safe / EXTENT) : k;
}

const icons = {};
for (const [name, S] of Object.entries(SHAPES)) {
  // Square and Maskable are only used at 180 px and up, so they have no small version
  const fits = S.r ? ['master', 'small'] : ['master'];
  for (const fit of fits) {
    const [x, y, w, h] = S.plate, k = glyphScale(S, fit);
    icons[fit === 'small' ? name + '/small' : name] = {
      plate: platePath(S), glyph: place(GLYPHS[fit], k, x + w / 2, y + h / 2), scale: k, shadow: S.shadow || null,
    };
  }
}

// glyph on a transparent canvas: iOS Dark (sized like Square) and the Android adaptive layers
const squareFit = glyphScale(SHAPES.Square, 'master');
const glyphOnly = {
  'ios-dark': { glyph: place(GLYPHS.master, squareFit, 512, 512), scale: squareFit },
  android: { glyph: place(GLYPHS.master, ANDROID_FG, 512, 512), scale: ANDROID_FG },
};

// the glyph's separate layers (planet, ring pieces), for the in-app logo SVGs: drawn one on top of
// another with the even-odd rule, as the Figma components are
const marks = {};
for (const [fit, o] of [['master', undefined], ['small', GLYPH.small]]) {
  const layers = GLYPH.glyph(o).map((l) => ({ name: l.name, d: l.d }));
  const nums = layers.flatMap((l) => l.d.replace(/[MLCZ]/g, ' ').trim().split(/[\s,]+/).map(Number));
  const xs = nums.filter((_, i) => i % 2 === 0), ys = nums.filter((_, i) => i % 2 === 1);
  marks[fit] = { box: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)], layers };
}

process.stdout.write(JSON.stringify({ looks: LOOKS, icons, glyphOnly, marks, roundedScale: icons.Rounded.scale }));
