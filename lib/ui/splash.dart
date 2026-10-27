// The launch animation: the Geared Ring mark comes together on the app icon's yellow while the app loads
// its projects and settings behind it, then fades into Home (or Welcome).
//
//   0 – 1.2 s    the planet grows into place; the gear ring turns in around it and meshes (a small overshoot)
//   1.1 – 1.7 s  "RoboCore IDE" rises in under the mark
//   1.5 – 2.2 s  a shine sweeps across the mark
//   2.2 – 3.7 s  the logo holds while the ring rocks gently (the app loads behind it)
//   3.7 – 4 s    a fade into the app. If the app is still loading at 3.7 s, the ring keeps rocking and
//                "Loading your projects…" shows until it is ready.
//
// With Windows' "Animation effects" off (MediaQuery.disableAnimations) it shows the finished logo and fades.
// In the web app the page already shows the mark while Flutter loads (web/index.html), so the mark starts in
// place and only the shine and the name play.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';
import 'widgets/brand.dart';

/// The mark's size on the splash; web/index.html draws its stand-in at the same width.
const kSplashMarkWidth = 200.0;
const _markAspect = 893.1 / 499.6; // app_mark.svg's viewBox

class Splash extends StatefulWidget {
  const Splash({super.key, required this.ready, required this.onDone});

  /// True once the app has loaded; the splash leaves after its intro and this.
  final bool ready;

  /// Called when the splash has faded out.
  final VoidCallback onDone;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 3700));
  late final _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  bool _started = false;

  /// The intro is over and the app is still loading.
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(_next);
    });
    _exit.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _intro.value = 1;
      _next();
    } else {
      // On the web the page's stand-in mark is already in place: start where the mark has landed.
      _intro.forward(from: kIsWeb ? .33 : 0);
      _idle.repeat();
    }
  }

  @override
  void didUpdateWidget(Splash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) _next();
  }

  /// After the intro: leave if the app is ready, otherwise keep rocking the ring and say it is loading.
  void _next() {
    if (_intro.status != AnimationStatus.completed || _exit.isAnimating || _exit.isCompleted) return;
    // The ring keeps rocking through the fade, so it never stops with a jump.
    _waiting = !widget.ready;
    if (widget.ready) _exit.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _idle.dispose();
    _exit.dispose();
    super.dispose();
  }

  /// [t] of the intro inside [begin, end], eased by [curve].
  double _at(double begin, double end, [Curve curve = Curves.linear]) =>
      Interval(begin, end, curve: curve).transform(_intro.value);

  @override
  Widget build(BuildContext context) {
    const markH = kSplashMarkWidth / _markAspect;
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _idle, _exit]),
      builder: (context, _) {
        // Planet: grows in with a little overshoot.
        final planetIn = _at(0, .27, Curves.easeOutBack);
        final planetFade = _at(0, .11);
        // Ring: turns in from a quarter turn back and settles as the gear meshes; later it rocks while loading.
        final ringIn = _at(.054, .324, Curves.easeOutBack);
        final ringFade = _at(.054, .162);
        // Once the logo is complete the ring rocks gently, easing in so it starts from rest.
        final rock = _at(.57, .68, Curves.easeInOut) * .06 * math.sin(_idle.value * 2 * math.pi);
        // Shine across the mark, then the name.
        final shine = _at(.405, .595, Curves.easeInOut);
        final name = _at(.297, .46, Curves.easeOutCubic);
        final out = Curves.easeIn.transform(_exit.value);

        final mark = SizedBox(
          width: kSplashMarkWidth,
          height: markH,
          child: Stack(fit: StackFit.expand, children: [
            Opacity(
              opacity: planetFade,
              child: Transform.scale(scale: .55 + .45 * planetIn, child: const _Part('assets/images/app_mark_planet.svg')),
            ),
            Opacity(
              opacity: ringFade,
              child: Transform.rotate(
                angle: -1.2 * (1 - ringIn) + rock,
                child: Transform.scale(scale: 1.35 - .35 * ringIn, child: const _Part('assets/images/app_mark_ring.svg')),
              ),
            ),
          ]),
        );

        return IgnorePointer(
          ignoring: _exit.isAnimating,
          child: Opacity(
            opacity: 1 - out,
            child: ColoredBox(
              color: kBrand,
              child: Stack(fit: StackFit.expand, children: [
                // The mark sits at the centre of the window (where web/index.html draws its stand-in).
                Center(
                  child: Transform.scale(
                    scale: 1 + .04 * out,
                    child: shine > 0 && shine < 1 ? _Shine(t: shine, child: mark) : mark,
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, markH / 2 + 46 + 12 * (1 - name)),
                    child: Opacity(
                      opacity: name,
                      child: Semantics(
                        label: 'RoboCore IDE',
                        child: ExcludeSemantics(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Wordmark(height: 30),
                            const SizedBox(width: 12),
                            Text('IDE',
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                    fontFamily: fDisplay, fontSize: 27, height: 1, fontWeight: FontWeight.w700, letterSpacing: .5, color: kNavy)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset(0, markH / 2 + 92),
                    child: AnimatedOpacity(
                      opacity: _waiting ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Text('Loading your projects…',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontFamily: fBody, fontSize: 14, fontWeight: FontWeight.w500, color: kNavy.withValues(alpha: .72))),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Part extends StatelessWidget {
  const _Part(this.asset);
  final String asset;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(asset, fit: BoxFit.contain, excludeFromSemantics: true);
}

/// A band of light across [child], [t] 0 → 1 from left to right, only where the child is drawn.
class _Shine extends StatelessWidget {
  const _Shine({required this.t, required this.child});
  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final x = -0.4 + 1.8 * t; // the band's centre, as a fraction of the width
          return LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
            stops: [(x - .18).clamp(0, 1), x.clamp(0, 1), (x + .18).clamp(0, 1)],
          ).createShader(rect);
        },
        child: child,
      );
}
