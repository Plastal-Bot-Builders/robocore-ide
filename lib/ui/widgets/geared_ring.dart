// The Geared Ring app icon drawn in code, so its gear ring can spin round the planet (the opening animation).
// A port of CONCEPTS.gearring in tools/app_icon/concepts.js and the helpers it uses in tools/app_icon/geom.js,
// the master behind every icon file; test/geared_ring_test.dart checks this port against it. At spin 0 it is
// the static icon (assets/images/app_icon.svg).
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A polygon corner: a point and the radius it is rounded with (0 = sharp).
typedef _Pt = ({double x, double y, double r});

/// The Geared Ring glyph and the Rounded app icon, on a 1024 × 1024 canvas.
abstract final class GearedRing {
  // CONCEPTS.gearring.defaults: the master glyph, drawn for the 824 px macOS plate.
  static const int teeth = 12;
  static const double _rTip = 400, _rRoot = 348, _wTip = 74, _wRoot = 100, _rIn = 254;
  static const double _squash = .42, _planet = 212, _gap = 22, _tilt = -20, _tipR = 5, _rootR = 6;
  static const double _c = 512; // canvas centre

  /// Degrees of spin after which the ring looks the same again (one tooth).
  static const double toothPitch = 360 / teeth;

  /// The glyph's scale on the full-canvas Rounded plate (tools/app_icon/layout.js `roundedScale`).
  static const double roundedScale = 450 / 404;

  /// The glyph at [spin] degrees as the even-odd path data of tools/app_icon/concepts.js: each closed
  /// polygon's rounded outline as `[command, x1, y1, …]` lists ('M', 'L', 'C', 'Z'). Used by the tests.
  static List<List<Object>> commands(double spin) => [for (final c in _contours(spin)) ..._outline(c)];

  /// The glyph at [spin] degrees (teeth travel left to right across the front for negative spin), even-odd.
  static Path glyph(double spin) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final contour in _contours(spin)) {
      for (final cmd in _outline(contour)) {
        final v = cmd.skip(1).cast<double>().toList();
        switch (cmd[0]) {
          case 'M':
            path.moveTo(v[0], v[1]);
          case 'L':
            path.lineTo(v[0], v[1]);
          case 'C':
            path.cubicTo(v[0], v[1], v[2], v[3], v[4], v[5]);
          case 'Z':
            path.close();
        }
      }
    }
    return path;
  }

  /// The Rounded plate (geom.js squircle: radius 229, corner smoothing 60 %), full canvas.
  static Path plate() => _squircle(0, 0, 1024, 1024, 229, .6);

  // ---------------------------------------------------------------------------------------------------------
  // CONCEPTS.gearring.glyph: planet (cut by the front of the ring) and ring (front half, plus the back half
  // where it shows beside the planet), in that order.
  static List<List<_Pt>> _contours(double spin) {
    const cx = _c, cy = _c, q = _squash;
    final th = _rad(_tilt);
    final outer = [
      for (final p in _gearPoints(_rad(spin))) (x: p.x, y: cy + (p.y - cy) * q, r: p.r),
    ];
    bool onAxis(_Pt p) => (p.y - cy).abs() < .01;
    List<_Pt> half(int sign) {
      final a = sign > 0 ? (x: cx - 2000, y: cy) : (x: cx + 2000, y: cy);
      final b = sign > 0 ? (x: cx + 2000, y: cy) : (x: cx - 2000, y: cy);
      final hp = _clipHalf(outer, a, b);
      var i = -1;
      for (var j = 0; j < hp.length; j++) {
        if (onAxis(hp[j]) && onAxis(hp[(j + 1) % hp.length])) {
          i = j;
          break;
        }
      }
      if (i < 0) return hp;
      final dir = hp[(i + 1) % hp.length].x > hp[i].x ? 1 : -1;
      final arc = _arcPts(cx, cy, _rIn, _rIn * q, sign, -dir * _rIn, dir * _rIn, 64);
      return [...hp.sublist(0, i + 1), ...arc, ...hp.sublist(i + 1)];
    }

    final front = half(1), back = half(-1);
    double sIn(double x) => math.sqrt(math.max(0, 1 - x * x / (_rIn * _rIn)));
    double sOut(double x) => math.sqrt(math.max(0, 1 - x * x / (_rTip * _rTip)));
    double hIn(double x) => _rIn * q * sIn(x) - _gap;
    double hOut(double x) => _rTip * q * sOut(x) + _gap;
    List<_Pt> Function(_Pt, _Pt) walkH(double Function(double) h) => (a, b) => [
          for (var j = 1; j < 24; j++)
            (x: a.x + (b.x - a.x) * j / 24, y: cy + h(a.x + (b.x - a.x) * j / 24 - cx), r: 0.0),
        ];
    final disc = _circlePts(cx, cy, _planet, 160);
    final pUp = _clipRegion(disc, (p) => p.y - cy < hIn(p.x - cx), walkH(hIn));
    final pDown = _clipRegion(disc, (p) => p.y - cy > hOut(p.x - cx), walkH(hOut));
    const rc = _planet + _gap;
    List<_Pt> walkC(_Pt a, _Pt b) {
      final a0 = math.atan2(a.y - cy, a.x - cx);
      var d = math.atan2(b.y - cy, b.x - cx) - a0;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      return [
        for (var j = 1; j < 20; j++)
          (x: cx + rc * math.cos(a0 + d * j / 20), y: cy + rc * math.sin(a0 + d * j / 20), r: 0.0),
      ];
    }

    List<_Pt> rot(List<_Pt> pts) => _rotPts(pts, cx, cy, th);
    final planet = [rot(pUp), if (pDown.length > 2) rot(pDown)];
    final ring = [rot(front)];
    for (final (p1, p2) in [
      ((x: cx, y: cy + 2000), (x: cx, y: cy - 2000)),
      ((x: cx, y: cy - 2000), (x: cx, y: cy + 2000)),
    ]) {
      final vis = _clipRegion(_clipHalf(back, p1, p2), (p) => _hypot(p.x - cx, p.y - cy) > rc, walkC);
      if (vis.length > 2) ring.add(rot(vis));
    }
    return [...planet, ...ring];
  }

  // ---- geom.js ----------------------------------------------------------------------------------------------
  static double _rad(double deg) => deg * math.pi / 180;
  static double _hypot(double x, double y) => math.sqrt(x * x + y * y);

  // gearPoints: root corner, tip arc, root corner, root arc per tooth; phase = spin (radians)
  static List<_Pt> _gearPoints(double phase) {
    const step = 2 * math.pi / teeth, arcStep = .035;
    final aT = math.asin(_wTip / 2 / _rTip), aR = math.asin(_wRoot / 2 / _rRoot);
    _Pt polar(double r, double a, double corner) => (x: _c + r * math.cos(a), y: _c + r * math.sin(a), r: corner);
    final pts = <_Pt>[];
    for (var i = 0; i < teeth; i++) {
      final t = phase + i * step;
      pts.add(polar(_rRoot, t - aR, _rootR));
      final m1 = math.max(1, (2 * aT / arcStep).round());
      for (var k = 0; k <= m1; k++) {
        pts.add(polar(_rTip, t - aT + 2 * aT * k / m1, k == 0 || k == m1 ? _tipR : 0.0));
      }
      pts.add(polar(_rRoot, t + aR, _rootR));
      final a0 = t + aR, a1 = t + step - aR, m2 = math.max(1, ((a1 - a0) / arcStep).round());
      for (var k = 1; k < m2; k++) {
        pts.add(polar(_rRoot, a0 + (a1 - a0) * k / m2, 0.0));
      }
    }
    return pts;
  }

  static List<_Pt> _circlePts(double cx, double cy, double r, int n) => [
        for (var i = 0; i < n; i++)
          (x: cx + r * math.cos(2 * math.pi * i / n), y: cy + r * math.sin(2 * math.pi * i / n), r: 0.0),
      ];

  // keeps the part of a polygon on the left of the directed line a→b
  static List<_Pt> _clipHalf(List<_Pt> pts, ({double x, double y}) a, ({double x, double y}) b) {
    double side(_Pt p) => (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    final out = <_Pt>[];
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length], sp = side(p), sq = side(q);
      if (sp >= 0) out.add(p);
      if ((sp >= 0) != (sq >= 0)) {
        final u = sp / (sp - sq);
        out.add((x: p.x + (q.x - p.x) * u, y: p.y + (q.y - p.y) * u, r: 0.0));
      }
    }
    return out;
  }

  // keeps the part where inside(p) holds; walk(exit, entry) follows the boundary between them
  static List<_Pt> _clipRegion(List<_Pt> pts, bool Function(_Pt) inside, List<_Pt> Function(_Pt, _Pt) walk) {
    final out = <(_Pt, String?)>[];
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final p = pts[i], q = pts[(i + 1) % n], ip = inside(p), iq = inside(q);
      if (ip) out.add((p, null));
      if (ip != iq) {
        var lo = 0.0, hi = 1.0;
        for (var k = 0; k < 40; k++) {
          final m = (lo + hi) / 2;
          if (inside((x: p.x + (q.x - p.x) * m, y: p.y + (q.y - p.y) * m, r: 0.0)) == ip) {
            lo = m;
          } else {
            hi = m;
          }
        }
        final u = (lo + hi) / 2;
        out.add(((x: p.x + (q.x - p.x) * u, y: p.y + (q.y - p.y) * u, r: 0.0), ip ? 'exit' : 'entry'));
      }
    }
    final res = <_Pt>[];
    for (var k = 0; k < out.length; k++) {
      res.add(out[k].$1);
      final next = out[(k + 1) % out.length];
      if (out[k].$2 == 'exit' && next.$2 == 'entry') res.addAll(walk(out[k].$1, next.$1));
    }
    return res;
  }

  // half an ellipse (lower for sign 1, upper for -1) from x0 to x1, cosine-spaced towards the pointed tips
  static List<_Pt> _arcPts(double cx, double cy, double a, double b, int sign, double x0, double x1, int n) {
    final pts = <_Pt>[];
    for (var i = 0; i <= n; i++) {
      final t = x0 + (x1 - x0) * (.5 - .5 * math.cos(math.pi * i / n));
      pts.add((x: cx + t, y: cy + sign * b * math.sqrt(math.max(0, 1 - t * t / (a * a))), r: 0.0));
    }
    return pts;
  }

  static List<_Pt> _rotPts(List<_Pt> pts, double cx, double cy, double ang) {
    final c = math.cos(ang), s = math.sin(ang);
    return [
      for (final p in pts) (x: cx + (p.x - cx) * c - (p.y - cy) * s, y: cy + (p.x - cx) * s + (p.y - cy) * c, r: p.r),
    ];
  }

  // roundPoly: each rounded corner becomes a line to its start and a cubic fillet; closed with 'Z'
  static List<List<Object>> _outline(List<_Pt> pts) {
    final n = pts.length;
    final segs = <List<Offset>>[]; // [a] for a sharp corner, [p1, c1, c2, p2] for a fillet
    for (var i = 0; i < n; i++) {
      final p = pts[i], a = pts[(i - 1 + n) % n], b = pts[(i + 1) % n];
      final at = Offset(p.x, p.y);
      if (p.r == 0) {
        segs.add([at]);
        continue;
      }
      final toA = Offset(a.x - p.x, a.y - p.y), toB = Offset(b.x - p.x, b.y - p.y);
      final u = _unit(toA), v = _unit(toB);
      final theta = math.acos((u.dx * v.dx + u.dy * v.dy).clamp(-1.0, 1.0));
      if (theta > math.pi - 1e-3) {
        segs.add([at]);
        continue;
      }
      final d = math.min(p.r / math.tan(theta / 2), math.min(toA.distance * .5, toB.distance * .5));
      final rr = d * math.tan(theta / 2);
      final h = 4 / 3 * math.tan((math.pi - theta) / 4) * rr;
      final p1 = at + u * d, p2 = at + v * d;
      segs.add([p1, p1 - u * h, p2 - v * h, p2]);
    }
    final start = segs[n - 1].last;
    return [
      ['M', start.dx, start.dy],
      for (final g in segs) ...[
        ['L', g.first.dx, g.first.dy],
        if (g.length == 4) ['C', g[1].dx, g[1].dy, g[2].dx, g[2].dy, g[3].dx, g[3].dy],
      ],
      ['Z'],
    ];
  }

  static Offset _unit(Offset o) {
    final l = o.distance;
    return l == 0 ? o : o / l;
  }

  // the figma-squircle construction of geom.js, the corner arc as one cubic
  static Path _squircle(double x, double y, double w, double h, double r, double s) {
    double rad(double deg) => deg * math.pi / 180;
    final maxR = math.min(w, h) / 2;
    r = math.min(r, maxR);
    final p = math.min((1 + s) * r, maxR);
    final arcMeasure = 90 * (1 - s);
    final arcLen = math.sin(rad(arcMeasure / 2)) * r * math.sqrt2;
    final alpha = (90 - arcMeasure) / 2;
    final p3p4 = r * math.tan(rad(alpha / 2));
    final beta = 45 * s;
    final c = p3p4 * math.cos(rad(beta));
    final d = c * math.tan(rad(beta));
    final b = (p - arcLen - c - d) / 3;
    final a = 2 * b;
    final arcH = 4 / 3 * math.tan(rad(arcMeasure / 4)) * r;
    final p1 = Offset(a + b + c, d);
    final p2 = p1 + Offset(arcLen, arcLen);
    final t1 = _unit(Offset(c, d)), t2 = _unit(Offset(d, c));
    final seg = [
      [Offset(a, 0), Offset(a + b, 0), p1],
      [p1 + t1 * arcH, p2 - t2 * arcH, p2],
      [p2 + Offset(d, c), p2 + Offset(d, b + c), p2 + Offset(d, a + b + c)],
    ];
    final corners = <(Offset, Offset Function(Offset))>[
      (Offset(x + w - p, y), (v) => v), // top right: along +x, turning to +y
      (Offset(x + w, y + h - p), (v) => Offset(-v.dy, v.dx)), // bottom right
      (Offset(x + p, y + h), (v) => -v), // bottom left
      (Offset(x, y + p), (v) => Offset(v.dy, -v.dx)), // top left
    ];
    final path = Path()..moveTo(x + p, y);
    for (final (o, rotate) in corners) {
      path.lineTo(o.dx, o.dy);
      for (final sg in seg) {
        final q = [for (final v in sg) o + rotate(v)];
        path.cubicTo(q[0].dx, q[0].dy, q[1].dx, q[1].dy, q[2].dx, q[2].dy);
      }
    }
    return path..close();
  }
}

/// The Rounded app icon (navy glyph on box yellow) with its gear ring turned [spin] degrees.
class GearedRingIconPainter extends CustomPainter {
  GearedRingIconPainter({required this.spin, this.plate = const Color(0xFFF2B01E), this.ink = const Color(0xFF1B2A41)});
  final double spin;
  final Color plate, ink;

  static final Path _plate = GearedRing.plate();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 1024, size.height / 1024)
      ..drawPath(_plate, Paint()..color = plate)
      ..translate(512, 512)
      ..scale(GearedRing.roundedScale)
      ..translate(-512, -512)
      ..drawPath(GearedRing.glyph(spin), Paint()..color = ink)
      ..restore();
  }

  @override
  bool shouldRepaint(GearedRingIconPainter old) => old.spin != spin || old.plate != plate || old.ink != ink;
}
