// ============================================================================
// App icon geometry: pure functions that return SVG path data using only absolute
// M / L / C / Z commands, so the same strings work in an SVG preview and in Figma
// (vectorPaths accept only those commands). Shared by app-icon/preview.js and the
// Figma plugin's icon page.
// ============================================================================

const IG = (() => {
  const K = 0.5522847498; // cubic handle length for a quarter circle
  const f = (v) => (Math.round(v * 100) / 100).toString();
  const pt = (p) => f(p[0]) + ' ' + f(p[1]);
  const polar = (cx, cy, r, a) => [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
  const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
  const mul = (a, k) => [a[0] * k, a[1] * k];
  const len = (a) => Math.hypot(a[0], a[1]);
  const unit = (a) => { const l = len(a) || 1; return [a[0] / l, a[1] / l]; };
  const rad = (deg) => (deg * Math.PI) / 180;

  // circle as 4 cubic arcs; dir = 1 clockwise on screen, -1 counter-clockwise (for holes)
  function circle(cx, cy, r, dir = 1) {
    const k = r * K, s = dir > 0 ? 1 : -1;
    return 'M' + pt([cx + r, cy]) +
      ' C' + pt([cx + r, cy + s * k]) + ' ' + pt([cx + k, cy + s * r]) + ' ' + pt([cx, cy + s * r]) +
      ' C' + pt([cx - k, cy + s * r]) + ' ' + pt([cx - r, cy + s * k]) + ' ' + pt([cx - r, cy]) +
      ' C' + pt([cx - r, cy - s * k]) + ' ' + pt([cx - k, cy - s * r]) + ' ' + pt([cx, cy - s * r]) +
      ' C' + pt([cx + k, cy - s * r]) + ' ' + pt([cx + r, cy - s * k]) + ' ' + pt([cx + r, cy]) + ' Z';
  }

  // closed polygon with filleted corners. pts: [[x, y, r], ...] (r = 0 → sharp corner)
  function roundPoly(pts) {
    const n = pts.length, segs = [];
    for (let i = 0; i < n; i++) {
      const P = pts[i], A = pts[(i - 1 + n) % n], B = pts[(i + 1) % n];
      const r = P[2] || 0;
      if (!r) { segs.push({ a: [P[0], P[1]] }); continue; }
      const u = unit(sub(A, P)), v = unit(sub(B, P));
      const theta = Math.acos(Math.max(-1, Math.min(1, u[0] * v[0] + u[1] * v[1])));
      if (theta > Math.PI - 1e-3) { segs.push({ a: [P[0], P[1]] }); continue; }
      let d = r / Math.tan(theta / 2);
      d = Math.min(d, len(sub(A, P)) * 0.5, len(sub(B, P)) * 0.5);
      const rr = d * Math.tan(theta / 2);              // radius actually achievable
      const h = (4 / 3) * Math.tan((Math.PI - theta) / 4) * rr;
      const p1 = add(P, mul(u, d)), p2 = add(P, mul(v, d));
      segs.push({ a: p1, b: p2, c1: add(p1, mul(mul(u, -1), h)), c2: add(p2, mul(mul(v, -1), h)) });
    }
    const endOf = (g) => g.b || g.a;
    let s = 'M' + pt(endOf(segs[n - 1]));
    for (let i = 0; i < n; i++) {
      const g = segs[i];
      s += ' L' + pt(g.a);
      if (g.b) s += ' C' + pt(g.c1) + ' ' + pt(g.c2) + ' ' + pt(g.b);
    }
    return s + ' Z';
  }

  // gear outline points. o = { cx, cy, n, rTip, rRoot, wTip, wRoot, rTipCorner, rRootCorner, phase, arcStep }
  // wTip / wRoot = tooth width in px at the tip circle and at the root circle
  function gearPoints(o) {
    const n = o.n, step = (2 * Math.PI) / n, ph = o.phase === undefined ? -Math.PI / 2 : o.phase;
    const aT = Math.asin(o.wTip / 2 / o.rTip), aR = Math.asin(o.wRoot / 2 / o.rRoot);
    const as = o.arcStep || 0.1, pts = [];
    for (let i = 0; i < n; i++) {
      const t = ph + i * step;
      pts.push([...polar(o.cx, o.cy, o.rRoot, t - aR), o.rRootCorner || 0]);
      const m1 = Math.max(1, Math.round((2 * aT) / as));
      const sk = o.skew || 0; // lean every tooth forward (clockwise) by this angle at the tip
      for (let k = 0; k <= m1; k++) pts.push([...polar(o.cx, o.cy, o.rTip, t + sk - aT + (2 * aT * k) / m1), (k === 0 || k === m1) ? (o.rTipCorner || 0) : 0]);
      pts.push([...polar(o.cx, o.cy, o.rRoot, t + aR), o.rRootCorner || 0]);
      const a0 = t + aR, a1 = t + step - aR, m2 = Math.max(1, Math.round((a1 - a0) / as));
      for (let k = 1; k < m2; k++) pts.push([...polar(o.cx, o.cy, o.rRoot, a0 + ((a1 - a0) * k) / m2), 0]);
    }
    return pts;
  }
  function gear(o) {
    let d = roundPoly(gearPoints(o));
    if (o.hole) d += ' ' + circle(o.cx, o.cy, o.hole, -1);
    return d;
  }

  // outline of an open polyline (centreline c) with width w; end corners rounded by rEnd,
  // the outer join by rOut and the inner join by rIn
  function strokePoly(c, w, rEnd, rOut, rIn) {
    const hw = w / 2, L = [], R = [];
    const nrm = (a, b) => { const d = unit(sub(b, a)); return [-d[1], d[0]]; };
    for (let i = 0; i < c.length; i++) {
      if (i === 0 || i === c.length - 1) {
        const nn = i === 0 ? nrm(c[0], c[1]) : nrm(c[i - 1], c[i]);
        L.push(add(c[i], mul(nn, hw))); R.push(add(c[i], mul(nn, -hw)));
      } else {
        const n1 = nrm(c[i - 1], c[i]), n2 = nrm(c[i], c[i + 1]);
        const m = unit(add(n1, n2)), k = hw / (m[0] * n1[0] + m[1] * n1[1]);
        L.push(add(c[i], mul(m, k))); R.push(add(c[i], mul(m, -k)));
      }
    }
    const e = rEnd === undefined ? hw * 0.95 : rEnd, ro = rOut === undefined ? hw * 0.6 : rOut, ri = rIn === undefined ? hw * 0.15 : rIn;
    const pts = [];
    L.forEach((p, i) => pts.push([p[0], p[1], (i === 0 || i === L.length - 1) ? e : ro]));
    R.slice().reverse().forEach((p, i) => pts.push([p[0], p[1], (i === 0 || i === R.length - 1) ? e : ri]));
    return { d: roundPoly(pts), L, R };
  }

  // chevron "<" (dir -1) or ">" (dir 1): tip at (x, y), arms reach `depth` back and `h` up/down
  function chevron(x, y, depth, h, w, dir, rEnd, rOut, rIn) {
    const back = x - dir * depth;
    // the stroke's outer point should sit at x, so move the centreline tip inwards by the miter half-length
    const ang = Math.atan2(h, depth);
    const miter = (w / 2) / Math.sin(ang);
    const tx = x - dir * miter;
    return strokePoly([[back - dir * 0, y - h], [tx, y], [back, y + h]], w, rEnd, rOut, rIn).d;
  }

  function rrect(x, y, w, h, r) {
    return roundPoly([[x, y, r], [x + w, y, r], [x + w, y + h, r], [x, y + h, r]]);
  }

  // Figma-style smoothed rounded rectangle ("squircle"): corner radius r, smoothing s (0..1).
  // Same construction as the figma-squircle library (MIT), with the arc converted to a cubic.
  function squircle(x, y, w, h, r, s) {
    s = s === undefined ? 0.6 : s;
    const maxR = Math.min(w, h) / 2;
    r = Math.min(r, maxR);
    const p = Math.min((1 + s) * r, maxR);
    const arcMeasure = 90 * (1 - s);
    const arcLen = Math.sin(rad(arcMeasure / 2)) * r * Math.SQRT2;
    const alpha = (90 - arcMeasure) / 2;
    const p3p4 = r * Math.tan(rad(alpha / 2));
    const beta = 45 * s;
    const c = p3p4 * Math.cos(rad(beta));
    const d = c * Math.tan(rad(beta));
    const b = (p - arcLen - c - d) / 3;
    const a = 2 * b;
    const arcH = (4 / 3) * Math.tan(rad(arcMeasure / 4)) * r;
    const P1 = [a + b + c, d];
    const P2 = [P1[0] + arcLen, P1[1] + arcLen];
    const t1 = unit([c, d]), t2 = unit([d, c]);
    const seg = [
      [[a, 0], [a + b, 0], P1],
      [add(P1, mul(t1, arcH)), sub(P2, mul(t2, arcH)), P2],
      [[P2[0] + d, P2[1] + c], [P2[0] + d, P2[1] + b + c], [P2[0] + d, P2[1] + a + b + c]],
    ];
    const corners = [
      { o: [x + w - p, y], R: (v) => [v[0], v[1]] },     // top-right: along +x, turning to +y
      { o: [x + w, y + h - p], R: (v) => [-v[1], v[0]] }, // bottom-right: along +y, turning to -x
      { o: [x + p, y + h], R: (v) => [-v[0], -v[1]] },    // bottom-left: along -x, turning to -y
      { o: [x, y + p], R: (v) => [v[1], -v[0]] },         // top-left: along -y, turning to +x
    ];
    let out = 'M' + pt([x + p, y]);
    for (const cr of corners) {
      out += ' L' + pt(cr.o);
      for (const sg of seg) {
        const q = sg.map((v) => add(cr.o, cr.R(v)));
        out += ' C' + pt(q[0]) + ' ' + pt(q[1]) + ' ' + pt(q[2]);
      }
    }
    return out + ' Z';
  }


  // ---- defiant gear helpers (2026-10-19, second round) ----
  // ratchet teeth: a ramp up to the tip, a short flat, then a straight radial drop (spins clockwise on screen)
  // o = { cx, cy, n, rTip, rRoot, ramp, flat (fractions of the tooth pitch), rTipCorner, rRootCorner, rFoot, phase, arcStep }
  function ratchetPoints(o) {
    const step = (2 * Math.PI) / o.n, ph = o.phase === undefined ? -Math.PI / 2 : o.phase, as = o.arcStep || 0.08, pts = [];
    for (let i = 0; i < o.n; i++) {
      const t = ph + i * step, a1 = t + o.ramp * step, a2 = a1 + o.flat * step;
      pts.push([...polar(o.cx, o.cy, o.rRoot, t), o.rFoot || 0]);
      // optional bulge: lifts the middle of the ramp so the flank reads as a tooth, not a saw blade
      if (o.bulge) { const u = 0.5; pts.push([...polar(o.cx, o.cy, o.rRoot + (o.rTip - o.rRoot) * u + o.bulge, t + (a1 - t) * u), 0]); }
      pts.push([...polar(o.cx, o.cy, o.rTip, a1), o.rTipCorner || 0]);
      const m = Math.max(1, Math.round((a2 - a1) / as));
      for (let k = 1; k < m; k++) pts.push([...polar(o.cx, o.cy, o.rTip, a1 + ((a2 - a1) * k) / m), 0]);
      pts.push([...polar(o.cx, o.cy, o.rTip, a2), o.rTipCorner || 0]);
      pts.push([...polar(o.cx, o.cy, o.rRoot, a2), o.rRootCorner || 0]);
      const m2 = Math.max(1, Math.round((t + step - a2) / as));
      for (let k = 1; k < m2; k++) pts.push([...polar(o.cx, o.cy, o.rRoot, a2 + ((t + step - a2) * k) / m2), 0]);
    }
    return pts;
  }
  // gear whose tooth i has its own tip radius (spiky bursts): o.rTips = [r0, r1, ...] repeats
  function burstPoints(o) {
    const step = (2 * Math.PI) / o.n, ph = o.phase === undefined ? -Math.PI / 2 : o.phase, as = o.arcStep || 0.08, pts = [];
    for (let i = 0; i < o.n; i++) {
      const t = ph + i * step, rT = o.rTips[i % o.rTips.length];
      const aR = Math.asin(o.wRoot / 2 / o.rRoot), aT = Math.asin(Math.max(0.5, o.wTip) / 2 / rT);
      pts.push([...polar(o.cx, o.cy, o.rRoot, t - aR), o.rRootCorner || 0]);
      pts.push([...polar(o.cx, o.cy, rT, t - aT), o.rTipCorner || 0]);
      if (o.wTip > 1) pts.push([...polar(o.cx, o.cy, rT, t + aT), o.rTipCorner || 0]);
      pts.push([...polar(o.cx, o.cy, o.rRoot, t + aR), o.rRootCorner || 0]);
      const a0 = t + aR, a1 = t + step - aR, m = Math.max(1, Math.round((a1 - a0) / as));
      for (let k = 1; k < m; k++) pts.push([...polar(o.cx, o.cy, o.rRoot, a0 + ((a1 - a0) * k) / m), 0]);
    }
    return pts;
  }
  // circle as a polygon (for clipping), clockwise unless dir = -1
  function circlePts(cx, cy, r, n, dir) {
    const pts = [];
    for (let i = 0; i < (n || 96); i++) { const a = (dir === -1 ? -1 : 1) * (2 * Math.PI * i) / (n || 96); pts.push([...polar(cx, cy, r, a), 0]); }
    return pts;
  }
  // solid ">" chevron polygon (dir 1) or "<" (dir -1): centre (cx, cy), half height h, depth d, horizontal thickness t
  function chevronPoly(cx, cy, h, d, t, dir, r) {
    const s = dir || 1, x0 = cx - s * (d + t) / 2;
    const P = [[x0, cy - h], [x0 + s * t, cy - h], [x0 + s * (t + d), cy], [x0 + s * t, cy + h], [x0, cy + h], [x0 + s * d, cy]];
    return (s > 0 ? P : P.reverse()).map((p) => [p[0], p[1], r || 0]);
  }
  // keep the part of a polygon on the left of the directed line a→b (Sutherland–Hodgman, one edge)
  function clipHalf(pts, a, b) {
    const side = (p) => (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
    const out = [];
    for (let i = 0; i < pts.length; i++) {
      const P = pts[i], Q = pts[(i + 1) % pts.length], sp = side(P), sq = side(Q);
      if (sp >= 0) out.push(P);
      if ((sp >= 0) !== (sq >= 0)) {
        const u = sp / (sp - sq);
        out.push([P[0] + (Q[0] - P[0]) * u, P[1] + (Q[1] - P[1]) * u, 0]);
      }
    }
    return out;
  }

  // clip a polygon to the left of a→b and carve a round hole (centre c, radius r) out of the cut edge,
  // so a gear sliced through its hub stays one simple outline per half
  function cutWithHole(pts, a, b, cx, cy, r, holeCorner) {
    const kept = clipHalf(pts, a, b);
    const L = Math.hypot(b[0] - a[0], b[1] - a[1]), dx = (b[0] - a[0]) / L, dy = (b[1] - a[1]) / L;
    const side = (p) => dx * (p[1] - a[1]) - dy * (p[0] - a[0]);
    const tOf = (p) => (p[0] - a[0]) * dx + (p[1] - a[1]) * dy;
    let i = -1;
    for (let k = 0; k < kept.length; k++) { const P = kept[k], Q = kept[(k + 1) % kept.length]; if (Math.abs(side(P)) < 0.01 && Math.abs(side(Q)) < 0.01) { i = k; break; } }
    if (i < 0) return kept;
    const fx = a[0] - cx, fy = a[1] - cy, B = fx * dx + fy * dy, C = fx * fx + fy * fy - r * r, disc = B * B - C;
    if (disc <= 0) return kept;
    const t1 = -B - Math.sqrt(disc), t2 = -B + Math.sqrt(disc);
    const H = (t) => [a[0] + dx * t, a[1] + dy * t];
    const P = kept[i], Q = kept[(i + 1) % kept.length];
    const up = tOf(Q) > tOf(P);
    const hs = up ? H(t1) : H(t2), he = up ? H(t2) : H(t1);
    const as = Math.atan2(hs[1] - cy, hs[0] - cx), ae = Math.atan2(he[1] - cy, he[0] - cx);
    let sweep = ae - as; while (sweep <= 0) sweep += 2 * Math.PI;      // try the positive way round
    const mid = [cx + r * Math.cos(as + sweep / 2), cy + r * Math.sin(as + sweep / 2)];
    if (side(mid) < 0) sweep -= 2 * Math.PI;                           // the arc must stay on the kept side
    const arc = [[hs[0], hs[1], holeCorner || 0]];
    const m = Math.max(4, Math.round(Math.abs(sweep) / 0.08));
    for (let k = 1; k < m; k++) arc.push([cx + r * Math.cos(as + (sweep * k) / m), cy + r * Math.sin(as + (sweep * k) / m), 0]);
    arc.push([he[0], he[1], holeCorner || 0]);
    return kept.slice(0, i + 1).concat(arc, kept.slice(i + 1));
  }

  // ---- orbit helpers (round 3: planet marks) ----
  const rotPts = (pts, cx, cy, ang) => { const c = Math.cos(ang), sn = Math.sin(ang); return pts.map((p) => [cx + (p[0] - cx) * c - (p[1] - cy) * sn, cy + (p[0] - cx) * sn + (p[1] - cy) * c, p[2] || 0]); };
  // keep the part of a polygon where inside(p) is true; walk(a, b) gives the boundary points between an
  // exit point a and the next entry point b. Works when the kept part is one piece.
  function clipRegion(pts, inside, walk) {
    const out = [], n = pts.length;
    for (let i = 0; i < n; i++) {
      const P = pts[i], Q = pts[(i + 1) % n], ip = inside(P), iq = inside(Q);
      if (ip) out.push([P[0], P[1], P[2] || 0, null]);
      if (ip !== iq) {
        let lo = 0, hi = 1;
        for (let k = 0; k < 40; k++) { const m = (lo + hi) / 2; if (inside([P[0] + (Q[0] - P[0]) * m, P[1] + (Q[1] - P[1]) * m]) === ip) lo = m; else hi = m; }
        const u = (lo + hi) / 2;
        out.push([P[0] + (Q[0] - P[0]) * u, P[1] + (Q[1] - P[1]) * u, 0, ip ? 'exit' : 'entry']);
      }
    }
    const res = [];
    for (let k = 0; k < out.length; k++) {
      res.push(out[k]);
      const nx = out[(k + 1) % out.length];
      if (out[k][3] === 'exit' && nx && nx[3] === 'entry') for (const w of walk(out[k], nx)) res.push(w);
    }
    return res.map((p) => [p[0], p[1], p[2] || 0]);
  }
  // half of an ellipse centred on (cx, cy) with half-width a: lower (sign 1) or upper (sign -1) arc, from x0 to x1
  function arcPts(cx, cy, a, b, sign, x0, x1, n) {
    const pts = [];
    for (let i = 0; i <= n; i++) {
      // cosine spacing puts more points near the pointed tips
      const t = x0 + (x1 - x0) * (0.5 - 0.5 * Math.cos(Math.PI * i / n));
      const sv = Math.sqrt(Math.max(0, 1 - (t * t) / (a * a)));
      pts.push([cx + t, cy + sign * b * sv, 0]);
    }
    return pts;
  }
  // four-point sparkle with slightly pinched sides
  function sparkle(cx, cy, r, k) {
    const pts = [];
    for (let i = 0; i < 8; i++) { const a = -Math.PI / 2 + (i * Math.PI) / 4, rr = i % 2 ? r * (k || 0.3) : r; pts.push([cx + rr * Math.cos(a), cy + rr * Math.sin(a), 0]); }
    return pts;
  }
  const movePts = (pts, dx, dy) => pts.map((p) => [p[0] + dx, p[1] + dy, p[2] || 0]);
  const scalePts = (pts, cx, cy, k) => pts.map((p) => [cx + (p[0] - cx) * k, cy + (p[1] - cy) * k, (p[2] || 0) * k]);

  return { circle, roundPoly, gearPoints, gear, strokePoly, chevron, rrect, squircle, polar, f, pt, rad, ratchetPoints, burstPoints, circlePts, chevronPoly, clipHalf, cutWithHole, movePts, scalePts, rotPts, clipRegion, arcPts, sparkle };
})();

if (typeof module !== 'undefined') module.exports = IG;
