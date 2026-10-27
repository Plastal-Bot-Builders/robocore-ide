// The Mac app's opening animation: the app icon grows in while its gear ring spins round the planet, slows down
// and settles on the still icon. A click or a key skips it; with Reduce motion on, the icon is still from the start.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'geared_ring.dart';

class LogoIntro extends StatefulWidget {
  const LogoIntro({super.key, this.size = 96, this.caption, this.onDone});

  /// The icon's size in logical pixels.
  final double size;

  /// Shown under the icon once the animation has settled (e.g. while the projects are still being read).
  final Widget? caption;

  /// Called once, when the animation ends or is skipped.
  final VoidCallback? onDone;

  /// The whole animation: [spinTime] of spinning, then a short rest on the still icon.
  static const duration = Duration(milliseconds: 1500);
  static const spinTime = Duration(milliseconds: 1250);
  static const appearTime = Duration(milliseconds: 280);

  /// How far the ring turns before it settles: five teeth, ending exactly on the still icon.
  static const spinDegrees = 5 * GearedRing.toothPitch;

  /// The ring's angle [t] into the animation: fastest at the start, slowing all the way to rest at 0 (a true
  /// cubic ease-out; Curves.easeOutCubic speeds up for a moment first). Decreasing angles carry the front
  /// teeth left to right across the planet.
  static double spinAt(Duration t) {
    final p = (t.inMicroseconds / spinTime.inMicroseconds).clamp(0.0, 1.0);
    return spinDegrees * math.pow(1 - p, 3);
  }

  @override
  State<LogoIntro> createState() => _LogoIntroState();
}

class _LogoIntroState extends State<LogoIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: LogoIntro.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  bool _started = false, _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    if (still) {
      // no motion: the still icon, and the app opens as soon as it is ready
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone?.call();
  }

  void _skip() {
    if (!_c.isCompleted) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent) _skip();
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = LogoIntro.duration * _c.value;
              final appear = Curves.easeOutCubic
                  .transform((t.inMicroseconds / LogoIntro.appearTime.inMicroseconds).clamp(0.0, 1.0));
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Semantics(
                  label: 'RoboCore',
                  image: true,
                  child: Opacity(
                    opacity: appear,
                    child: Transform.scale(
                      scale: .86 + .14 * appear,
                      child: CustomPaint(
                        size: Size.square(widget.size),
                        painter: GearedRingIconPainter(spin: LogoIntro.spinAt(t)),
                      ),
                    ),
                  ),
                ),
                if (widget.caption != null) ...[
                  const SizedBox(height: 16),
                  AnimatedOpacity(
                    opacity: _c.isCompleted ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: widget.caption,
                  ),
                ],
              ]);
            },
          ),
        ),
      ),
    );
  }
}
