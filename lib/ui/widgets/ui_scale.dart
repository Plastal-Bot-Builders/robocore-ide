// The size of the whole interface (Settings → Appearance → Display size). The design is drawn for a 1440 × 900
// screen, a 13 or 14 inch MacBook; on a bigger screen (a 16 inch MacBook shows 1728 × 1117) everything at that size
// looks small and leaves empty space, so Auto scales the app to the screen it is on.
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

/// The sizes Settings offers (Auto is 0) and the View menu steps through.
const kUiScales = [0.9, 1.0, 1.1, 1.25, 1.5];

/// Auto: on a computer, the screen's size against the design's 1440 × 900, from 100 % to 150 % in 5 % steps; screens
/// up to about 1580 points wide stay at 100 %. The web app leaves it to the browser's own zoom (⌘ + and ⌘ −), and
/// phones and tablets stay at 100 %.
double autoUiScale(BuildContext context) {
  const computers = {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux};
  if (kIsWeb || !computers.contains(defaultTargetPlatform)) return 1;
  try {
    final d = View.of(context).display;
    final w = d.size.width / d.devicePixelRatio, h = d.size.height / d.devicePixelRatio;
    if (!(w > 0 && h > 0)) return 1;
    final s = math.min(w / 1440, h / 900);
    return s < 1.1 ? 1 : (s.clamp(1.0, 1.5) * 20).round() / 20;
  } catch (_) {
    return 1; // no display reported
  }
}

/// The next size up ([dir] 1) or down (-1) from [current], within [kUiScales].
double stepUiScale(double current, int dir) {
  if (dir > 0) return kUiScales.firstWhere((s) => s > current + .001, orElse: () => kUiScales.last);
  return kUiScales.lastWhere((s) => s < current - .001, orElse: () => kUiScales.first);
}

/// Lays the app out for a screen [scale] times smaller and draws it [scale] times bigger, so every size in the app
/// grows together (text stays sharp: it is drawn at the screen's resolution). [setting] 0 is Auto.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.setting, required this.child});
  final double setting;
  final Widget child;

  /// The scale in use, 1 outside a UiScale.
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Scale>()?.scale ?? 1;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = setting > 0 ? setting : autoUiScale(context);
    // The same widgets at every scale, so changing it keeps the app's state; at 100 % the app sees exactly what it
    // would without this.
    return _Scale(
      scale: s,
      child: LayoutBuilder(builder: (context, box) {
        final size = box.biggest / s;
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: s == 1
                  ? mq
                  : mq.copyWith(
                      size: size,
                      devicePixelRatio: mq.devicePixelRatio * s,
                      padding: mq.padding / s,
                      viewPadding: mq.viewPadding / s,
                      viewInsets: mq.viewInsets / s,
                    ),
              child: child,
            ),
          ),
        );
      }),
    );
  }
}

class _Scale extends InheritedWidget {
  const _Scale({required this.scale, required super.child});
  final double scale;

  @override
  bool updateShouldNotify(_Scale old) => scale != old.scale;
}
