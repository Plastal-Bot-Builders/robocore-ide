// Icon concepts on a 1024 × 1024 canvas (centre 512). Each concept returns its glyph as
// layers: [{ name, d, role }] where role picks the colour from the active theme
// ('ink' = main glyph colour, 'accent' = second colour, 'hole' = cut-outs drawn in the plate colour).
// IG (geom.js) is a global here: concatenated before this file in the plugin, set on globalThis by preview.js.
const ICX = 512, ICY = 512;

// the RoboCore logo gear, simplified: 8 teeth, round hub
function coreGear(cx, cy, s, extra) {
  return IG.gear(Object.assign({
    cx, cy, n: 8, rTip: 132 * s, rRoot: 104 * s, wTip: 50 * s, wRoot: 70 * s,
    rTipCorner: 9 * s, rRootCorner: 12 * s, hole: 44 * s,
  }, extra || {}));
}

const CONCEPTS = {
  // 1 — code brackets around the RoboCore gear: ‹ ⚙ ›
  brackets: {
    title: 'Core Brackets',
    note: 'Code chevrons around the RoboCore gear. Reads as "code" first, robotics second.',
    // master proportions (1024 canvas, glyph sized for the 824 px macOS plate)
    defaults: { stroke: 88, h: 164, depth: 132, gap: 314, gearScale: 1.18, gear: { hole: 50 } },
    // tuned for 16–32 px on a full-canvas plate: heavier strokes, 6-tooth gear, bigger hub
    small: { stroke: 132, h: 250, depth: 168, gap: 404, gearScale: 1.62, gear: { n: 6, wTip: 92, wRoot: 120, rTipCorner: 10, rRootCorner: 10, hole: 66 } },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const w = o.stroke, h = o.h, depth = o.depth, gap = o.gap;
      return [
        { name: 'Bracket left', role: 'ink', d: IG.chevron(ICX - gap, ICY, depth, h, w, -1) },
        { name: 'Bracket right', role: 'ink', d: IG.chevron(ICX + gap, ICY, depth, h, w, 1) },
        { name: 'Core gear', role: 'accent', d: coreGear(ICX, ICY, o.gearScale || 1, o.gear) },
      ];
    },
  },

  // 2 — the gear opens into a "C" (Code / Core / Cog) with a prompt caret inside
  opencog: {
    title: 'Open Cog',
    note: 'The gear opens like a C toward a prompt caret: the robot\'s core, ready for code.',
    glyph(o = {}) {
      const rT = 300, rR = 250, rIn = 168, n = 10;
      const open = IG.rad(o.open || 34);             // half-angle of the opening (right side)
      const step = (2 * Math.PI) / n;
      // teeth centred away from the opening: phase so that one tooth sits at 180°
      const all = IG.gearPoints({ cx: ICX, cy: ICY, n, rTip: rT, rRoot: rR, wTip: 64, wRoot: 92, rTipCorner: 10, rRootCorner: 14, phase: Math.PI / 10, arcStep: 0.06 });
      const angOf = (p) => { let a = Math.atan2(p[1] - ICY, p[0] - ICX); return a; };
      // keep outer points outside the opening wedge (|angle| > open), ordered clockwise starting just below the opening
      const keep = all.filter((p) => Math.abs(angOf(p)) > open + 0.0001);
      // rotate list so it starts at the first point after the opening (angle just above +open, clockwise = increasing)
      const sorted = keep.map((p) => ({ p, a: (angOf(p) - open + 2 * Math.PI) % (2 * Math.PI) })).sort((x, y) => x.a - y.a).map((x) => x.p);
      const endR = rR - 6;
      const pts = [];
      pts.push([...IG.polar(ICX, ICY, endR, open), 22]);
      sorted.forEach((p) => pts.push(p));
      pts.push([...IG.polar(ICX, ICY, endR, -open), 22]);
      // inner arc back, counter-clockwise from -open to +open (through 180°)
      const m = 40;
      for (let k = 0; k <= m; k++) {
        const a = -open - ((2 * Math.PI - 2 * open) * k) / m;
        pts.push([...IG.polar(ICX, ICY, rIn, a), (k === 0 || k === m) ? 22 : 0]);
      }
      const ring = IG.roundPoly(pts);
      const caret = IG.chevron(ICX + 70, ICY, 92, 112, 70, 1);
      return [
        { name: 'Open cog', role: 'ink', d: ring },
        { name: 'Caret', role: 'accent', d: caret },
      ];
    },
  },

  // 3 — a friendly robot head whose face is a prompt: > _
  bot: {
    title: 'Bot Prompt',
    note: 'A robot head whose face is a command prompt (>_), which also reads as a wink.',
    glyph() {
      const head = IG.squircle(ICX - 270, ICY - 190, 540, 430, 150, 0.6);
      const screen = IG.squircle(ICX - 196, ICY - 118, 392, 286, 92, 0.6);
      const earL = IG.rrect(ICX - 318, ICY - 40, 60, 140, 26);
      const earR = IG.rrect(ICX + 258, ICY - 40, 60, 140, 26);
      const stem = IG.rrect(ICX - 22, ICY - 268, 44, 90, 14);
      const ball = IG.circle(ICX, ICY - 282, 44);
      const eye = IG.chevron(ICX - 78, ICY + 22, 70, 62, 52, 1);
      const bar = IG.rrect(ICX + 22, ICY + 60, 112, 50, 22);
      return [
        { name: 'Head', role: 'ink', d: head + ' ' + earL + ' ' + earR + ' ' + stem + ' ' + ball },
        { name: 'Face', role: 'face', d: screen },
        { name: 'Prompt', role: 'accent2', d: eye + ' ' + bar },
      ];
    },
  },
  // ---- round 2 (2026-10-19): keep the gear, make it defiant ----
  // a ratchet only turns one way: sharp sloped teeth, a > prompt punched through the hub
  ratchet: {
    title: 'Ratchet',
    note: 'Ratchet teeth that only turn one way, with a > prompt punched through the hub.',
    defaults: { n: 9, rTip: 306, rRoot: 236, ramp: 0.52, flat: 0.15, phase: -Math.PI / 2 - 0.12, chev: [112, 96, 74] },
    small: { n: 7, rTip: 404, rRoot: 300, ramp: 0.5, flat: 0.2, phase: -Math.PI / 2 - 0.12, chev: [150, 120, 108] },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const k = o.rTip / 306;
      const body = IG.ratchetPoints({ cx: ICX, cy: ICY, n: o.n, rTip: o.rTip, rRoot: o.rRoot, ramp: o.ramp, flat: o.flat, phase: o.phase, rTipCorner: 6 * k, rRootCorner: 10 * k, rFoot: 18 * k });
      const [h, d, t] = o.chev;
      const hole = IG.chevronPoly(ICX + 12 * k, ICY, h, d, t, 1, 10 * k);
      return [{ name: 'Gear', role: 'accent', d: IG.roundPoly(body) + ' ' + IG.roundPoly(hole) }];
    },
  },
  // the gear sliced by a "/" and knocked out of line: broken, not beaten
  split: {
    title: 'Split Gear',
    note: 'A heavy gear sliced by a / (code\'s own slash) with one half knocked forward.',
    defaults: { n: 8, rTip: 306, rRoot: 244, wTip: 90, wRoot: 134, hole: 96, gap: 17, slide: 22, angle: 62, phase: -Math.PI / 2 + Math.PI / 8 },
    small: { n: 6, rTip: 404, rRoot: 316, wTip: 150, wRoot: 210, hole: 120, gap: 26, slide: 30, angle: 62, phase: -Math.PI / 2 + Math.PI / 6 },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const k = o.rTip / 306;
      const outer = IG.gearPoints({ cx: ICX, cy: ICY, n: o.n, rTip: o.rTip, rRoot: o.rRoot, wTip: o.wTip, wRoot: o.wRoot, rTipCorner: 5 * k, rRootCorner: 9 * k, phase: o.phase, arcStep: 0.05 });
      const dir = [Math.cos(IG.rad(o.angle)), -Math.sin(IG.rad(o.angle))];   // up and to the right: "/"
      const nrm = [-dir[1], dir[0]];
      const at = (off, t) => [ICX + nrm[0] * off + dir[0] * t, ICY + nrm[1] * off + dir[1] * t];
      // upper-left half: left of the line going up; lower-right half: the other side
      const ul = IG.cutWithHole(outer, at(-o.gap, -600), at(-o.gap, 600), ICX, ICY, o.hole, 0);
      const lr = IG.cutWithHole(outer, at(o.gap, 600), at(o.gap, -600), ICX, ICY, o.hole, 0);
      const slid = IG.movePts(ul, dir[0] * o.slide, dir[1] * o.slide);
      return [
        { name: 'Gear half (lit)', role: 'accent', d: IG.roundPoly(slid) },
        { name: 'Gear half (shade)', role: 'accentShade', d: IG.roundPoly(lr) },
      ];
    },
  },
  // all spikes: a gear that has become a burst of energy
  burst: {
    title: 'Spike Gear',
    note: 'Teeth sharpened into spikes, long and short, around a solid hub.',
    defaults: { n: 12, rTips: [316, 262], rRoot: 204, wRoot: 104, hole: 80 },
    small: { n: 8, rTips: [410, 340], rRoot: 270, wRoot: 170, hole: 104 },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const pts = IG.burstPoints({ cx: ICX, cy: ICY, n: o.n, rTips: o.rTips, rRoot: o.rRoot, wTip: 0, wRoot: o.wRoot, rTipCorner: 3, rRootCorner: 8, phase: -Math.PI / 2 });
      return [{ name: 'Gear', role: 'accent', d: IG.roundPoly(pts) + ' ' + IG.circle(ICX, ICY, o.hole, -1) }];
    },
  },
  // the RoboCore gear, sharpened: every tooth leans forward, a > prompt is cut through the hub
  slant: {
    title: 'Forward Gear',
    note: 'The RoboCore gear, sharpened: every tooth leans forward, a > prompt is cut through the hub and a hard / of light splits it.',
    defaults: { n: 8, rTip: 306, rRoot: 240, wTip: 86, wRoot: 124, skew: 7, tipR: 4, rootR: 10, hub: 'chevron', chev: [110, 94, 78], hole: 92, phase: -90, facet: true },
    small: { n: 6, rTip: 404, rRoot: 314, wTip: 150, wRoot: 200, skew: 8, tipR: 10, rootR: 16, hub: 'chevron', chev: [150, 120, 112], hole: 120, phase: -90, facet: false },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const k = o.rTip / 306;
      const outer = IG.gearPoints({ cx: ICX, cy: ICY, n: o.n, rTip: o.rTip, rRoot: o.rRoot, wTip: o.wTip, wRoot: o.wRoot, skew: IG.rad(o.skew), rTipCorner: o.tipR * k, rRootCorner: o.rootR * k, phase: IG.rad(o.phase), arcStep: 0.06 });
      let d = IG.roundPoly(outer);
      if (o.hub === 'chevron') { const [h, dd, t] = o.chev; d += ' ' + IG.roundPoly(IG.chevronPoly(ICX + 10 * k, ICY, h, dd, t, 1, 8 * k)); }
      else if (o.hub === 'circle') d += ' ' + IG.circle(ICX, ICY, o.hole, -1);
      return [{ name: o.facet ? 'Gear' : 'Gear (flat)', role: o.facet ? 'facet' : 'accent', d }];
    },
  },
  // round 3 (2026-10-19): the gear as a planet inside a tapered orbit ring, in one ink, after Fred's planet-logo sheet
  orbit: {
    title: 'Orbit Gear',
    note: 'The RoboCore gear as a planet, with a tapered orbit ring sweeping across it, in one ink.',
    defaults: { n: 8, rTip: 262, rRoot: 214, wTip: 82, wRoot: 112, tipR: 8, rootR: 10, phase: 0, tilt: -22, a: 396, front: [70, 166], back: [86, 104], gap: 24, ring: 'full', face: 'none', spark: null, moon: null, dy: 0 },
    // 16–32 px: 6 teeth, a bolder ring that only passes in front, and no slice of gear below it
    small: { n: 6, rTip: 310, rRoot: 244, wTip: 146, wRoot: 190, tipR: 10, rootR: 12, phase: 0, tilt: -22, a: 486, front: [120, 250], back: [104, 130], gap: 46, ring: 'front', hideBelow: true, face: 'none', spark: null, moon: null, dy: -20 },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const cx = ICX, cy = ICY + o.dy, th = IG.rad(o.tilt), k = o.rTip / 262;
      const s = (x) => Math.sqrt(Math.max(0, 1 - (x * x) / (o.a * o.a)));
      const hIn = (x) => o.front[0] * s(x) - o.gap, hOut = (x) => o.front[1] * s(x) + o.gap;
      const walkH = (h) => (A, B) => { const r = []; for (let i = 1; i < 24; i++) { const x = A[0] + (B[0] - A[0]) * i / 24; r.push([x, cy + h(x - cx), 0]); } return r; };
      // gear without a hub, in the ring's frame (ring along x)
      const gear = IG.rotPts(IG.gearPoints({ cx, cy, n: o.n, rTip: o.rTip, rRoot: o.rRoot, wTip: o.wTip, wRoot: o.wRoot, rTipCorner: o.tipR * k, rRootCorner: o.rootR * k, phase: -Math.PI / 2 + IG.rad(o.phase) - th, arcStep: 0.05 }), cx, cy, 0);
      const front = o.ring !== 'none';
      const upper = front ? IG.clipRegion(gear, (p) => p[1] - cy < hIn(p[0] - cx), walkH(hIn)) : gear;
      const lower = front && !o.hideBelow ? IG.clipRegion(gear, (p) => p[1] - cy > hOut(p[0] - cx), walkH(hOut)) : null;
      const back = (o.ring === 'full');
      const rc = o.rTip + o.gap;
      const walkC = (A, B) => {
        let a0 = Math.atan2(A[1] - cy, A[0] - cx), a1 = Math.atan2(B[1] - cy, B[0] - cx), d = a1 - a0;
        while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI;
        const r = []; for (let i = 1; i < 16; i++) { const a = a0 + d * i / 16; r.push([cx + rc * Math.cos(a), cy + rc * Math.sin(a), 0]); } return r;
      };
      const uniq = (pts) => pts.filter((p, i) => { const q = pts[(i + 1) % pts.length]; return Math.hypot(p[0] - q[0], p[1] - q[1]) > 0.01; });
      const crescent = (bOut, bIn, sign) => uniq(IG.arcPts(cx, cy, o.a, bOut, sign, -o.a, o.a, 96).concat(IG.arcPts(cx, cy, o.a, bIn, sign, o.a, -o.a, 96)));
      const R = (pts) => IG.rotPts(pts, cx, cy, th);
      const layers = [];
      let gearD = IG.roundPoly(R(upper));
      if (lower && lower.length > 2) gearD += ' ' + IG.roundPoly(R(lower));
      if (o.face === 'eyes') for (const sx of [-1, 1]) gearD += ' ' + IG.circle(cx + sx * 66 * k, cy - 70 * k, 30 * k, -1);
      if (o.face === 'prompt') gearD += ' ' + IG.roundPoly(IG.chevronPoly(cx + 6 * k, cy - 86 * k, 62 * k, 54 * k, 46 * k, 1, 6 * k));
      if (o.face === 'hub') gearD += ' ' + IG.circle(cx, cy - 92 * k, 46 * k, -1);
      layers.push({ name: 'Planet gear', role: 'ink', d: gearD });
      if (front) {
        let ringD = IG.roundPoly(R(crescent(o.front[1], o.front[0], 1)));
        if (back) {
          const B = crescent(o.back[1], o.back[0], -1);
          for (const [p1, p2] of [[[cx, cy + 2000], [cx, cy - 2000]], [[cx, cy - 2000], [cx, cy + 2000]]]) {
            const half = IG.clipHalf(B, p1, p2);
            const vis = IG.clipRegion(half, (p) => Math.hypot(p[0] - cx, p[1] - cy) > rc, walkC);
            if (vis.length > 2) ringD += ' ' + IG.roundPoly(R(vis));
          }
        }
        layers.push({ name: 'Orbit ring', role: 'ink', d: ringD });
      }
      if (o.spark) layers.push({ name: 'Spark', role: 'ink', d: IG.roundPoly(IG.sparkle(cx + o.spark[0], cy + o.spark[1], o.spark[2], 0.26)) });
      if (o.moon) layers.push({ name: 'Moon', role: 'ink', d: IG.circle(cx + o.moon[0], cy + o.moon[1], o.moon[2]) });
      return layers;
    },
  },
  // round 3b (2026-10-19, Fred's pick from four sketches): a smooth planet whose ring is a gear, seen in perspective
  gearring: {
    title: 'Geared Ring',
    note: 'A planet whose ring is the RoboCore gear, seen edge-on: teeth all the way round, in one ink.',
    defaults: { n: 12, rTip: 400, rRoot: 348, wTip: 74, wRoot: 100, rIn: 254, squash: 0.42, planet: 212, gap: 22, tilt: -20, tipR: 5, rootR: 6, face: 'none', moon: null },
    // 16–32 px: fewer, bigger teeth, a thicker ring and a bigger planet on a full-canvas plate
    small: { n: 10, rTip: 470, rRoot: 398, wTip: 104, wRoot: 136, rIn: 300, squash: 0.44, planet: 250, gap: 36, tilt: -20, tipR: 8, rootR: 8, face: 'none', moon: null },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const cx = ICX, cy = ICY, th = IG.rad(o.tilt), q = o.squash, k = o.rTip / 400;
      const sq = (pts) => pts.map((p) => [p[0], cy + (p[1] - cy) * q, (p[2] || 0)]);
      // the gear ring, flattened into an ellipse (ring frame: axis along x)
      const outer = sq(IG.gearPoints({ cx, cy, n: o.n, rTip: o.rTip, rRoot: o.rRoot, wTip: o.wTip, wRoot: o.wRoot, rTipCorner: o.tipR, rRootCorner: o.rootR, phase: 0, arcStep: 0.035 }));
      const onAxis = (p) => Math.abs(p[1] - cy) < 0.01;
      // half of the ring: half of the toothed disc with the half inner ellipse carved out of its straight edge
      const half = (sign) => {
        const a = sign > 0 ? [cx - 2000, cy] : [cx + 2000, cy], b = sign > 0 ? [cx + 2000, cy] : [cx - 2000, cy];
        const hp = IG.clipHalf(outer, a, b);                       // keeps y >= cy (front) or y <= cy (back)
        let i = -1;
        for (let j = 0; j < hp.length; j++) if (onAxis(hp[j]) && onAxis(hp[(j + 1) % hp.length])) { i = j; break; }
        if (i < 0) return hp;
        const P = hp[i], Q = hp[(i + 1) % hp.length];
        const dir = Q[0] > P[0] ? 1 : -1;
        const arc = IG.arcPts(cx, cy, o.rIn, o.rIn * q, sign, -dir * o.rIn, dir * o.rIn, 64).map((p) => [p[0], p[1], 0]);
        return hp.slice(0, i + 1).concat(arc, hp.slice(i + 1));
      };
      const front = half(1), back = half(-1);
      // planet: cut by the front of the ring (plus a gap) — above the inner edge and below the tooth tips
      const sIn = (x) => Math.sqrt(Math.max(0, 1 - (x * x) / (o.rIn * o.rIn)));
      const sOut = (x) => Math.sqrt(Math.max(0, 1 - (x * x) / (o.rTip * o.rTip)));
      const hIn = (x) => o.rIn * q * sIn(x) - o.gap, hOut = (x) => o.rTip * q * sOut(x) + o.gap;
      const walkH = (h) => (A, B) => { const r = []; for (let j = 1; j < 24; j++) { const x = A[0] + (B[0] - A[0]) * j / 24; r.push([x, cy + h(x - cx), 0]); } return r; };
      const disc = IG.circlePts(cx, cy, o.planet, 160);
      const pUp = IG.clipRegion(disc, (p) => p[1] - cy < hIn(p[0] - cx), walkH(hIn));
      const pDown = IG.clipRegion(disc, (p) => p[1] - cy > hOut(p[0] - cx), walkH(hOut));
      // back of the ring: hidden behind the planet (plus a gap), left and right pieces clipped separately
      const rc = o.planet + o.gap;
      const walkC = (A, B) => {
        const a0 = Math.atan2(A[1] - cy, A[0] - cx); let d = Math.atan2(B[1] - cy, B[0] - cx) - a0;
        while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI;
        const r = []; for (let j = 1; j < 20; j++) { const a = a0 + d * j / 20; r.push([cx + rc * Math.cos(a), cy + rc * Math.sin(a), 0]); } return r;
      };
      const R = (pts) => IG.rotPts(pts, cx, cy, th);
      let ringD = IG.roundPoly(R(front));
      for (const [p1, p2] of [[[cx, cy + 2000], [cx, cy - 2000]], [[cx, cy - 2000], [cx, cy + 2000]]]) {
        const vis = IG.clipRegion(IG.clipHalf(back, p1, p2), (p) => Math.hypot(p[0] - cx, p[1] - cy) > rc, walkC);
        if (vis.length > 2) ringD += ' ' + IG.roundPoly(R(vis));
      }
      let planetD = IG.roundPoly(R(pUp));
      if (pDown.length > 2) planetD += ' ' + IG.roundPoly(R(pDown));
      if (o.face === 'prompt') planetD += ' ' + IG.roundPoly(IG.chevronPoly(cx + 8 * k, cy - 70 * k, 56 * k, 50 * k, 42 * k, 1, 6 * k));
      if (o.face === 'eyes') for (const sx of [-1, 1]) planetD += ' ' + IG.circle(cx + sx * 58 * k, cy - 74 * k, 26 * k, -1);
      const layers = [{ name: 'Planet', role: 'ink', d: planetD }, { name: 'Gear ring', role: 'ink', d: ringD }];
      if (o.moon) layers.push({ name: 'Moon', role: 'ink', d: IG.circle(cx + o.moon[0], cy + o.moon[1], o.moon[2]) });
      return layers;
    },
  },
  // a solid gear with a sharp run arrow cut through it
  run: {
    title: 'Run Gear',
    note: 'A solid, chunky gear with a sharp Run / Upload arrow cut clean through it.',
    defaults: { n: 8, rTip: 306, rRoot: 248, wTip: 92, wRoot: 134, tri: 112 },
    small: { n: 6, rTip: 404, rRoot: 320, wTip: 150, wRoot: 210, tri: 150 },
    glyph(o) {
      o = Object.assign({}, this.defaults, o || {});
      const k = o.rTip / 306, t = o.tri;
      const outer = IG.gearPoints({ cx: ICX, cy: ICY, n: o.n, rTip: o.rTip, rRoot: o.rRoot, wTip: o.wTip, wRoot: o.wRoot, rTipCorner: 6 * k, rRootCorner: 10 * k, phase: -Math.PI / 2 + Math.PI / o.n });
      const tri = [[ICX - t * 0.62, ICY - t, 14 * k], [ICX + t * 1.08, ICY, 14 * k], [ICX - t * 0.62, ICY + t, 14 * k]];
      return [{ name: 'Gear', role: 'accent', d: IG.roundPoly(outer) + ' ' + IG.roundPoly(tri) }];
    },
  },
};

if (typeof module !== 'undefined') module.exports = { CONCEPTS, coreGear, ICX, ICY };
