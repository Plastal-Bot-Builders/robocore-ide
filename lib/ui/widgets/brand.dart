// The RoboCore IDE logo, as in the Figma design (Logo/Mark, Logo/Wordmark, Logo/Product Lockup,
// Logo/App Icon). app_mark.svg and app_icon.svg come from tools/gen_app_icons.py, the same master
// as the platform icons; wordmark.svg is the RoboCore wordmark (gear "o").
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme.dart';

/// The Geared Ring mark (the app icon's glyph, small version) in one ink.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.height = 24, this.color = kNavy});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset('assets/images/app_mark.svg',
      height: height, colorFilter: ColorFilter.mode(color, BlendMode.srcIn), excludeFromSemantics: true);
}

/// The RoboCore wordmark in one ink.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 22, this.color = kNavy});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset('assets/images/wordmark.svg',
      height: height, colorFilter: ColorFilter.mode(color, BlendMode.srcIn), excludeFromSemantics: true);
}

/// Mark + wordmark + "IDE": the top-bar lockup. [scale] 1 is the design size (mark 24, wordmark 22).
class ProductLockup extends StatelessWidget {
  const ProductLockup({super.key, this.scale = 1, this.color = kNavy, this.product = true});
  final double scale;
  final Color color;
  final bool product;

  @override
  Widget build(BuildContext context) => Semantics(
        label: product ? 'RoboCore IDE' : 'RoboCore',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppMark(height: 24 * scale, color: color),
          SizedBox(width: 10 * scale),
          Wordmark(height: 22 * scale, color: color),
          if (product) ...[
            SizedBox(width: 10 * scale),
            Text('IDE',
                style: TextStyle(
                    fontFamily: fDisplay,
                    fontSize: 20 * scale,
                    height: 24 / 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4 * scale,
                    color: color)),
          ],
        ]),
      );
}

/// The app icon as the operating system shows it (Rounded shape, navy on box yellow).
class AppIconTile extends StatelessWidget {
  const AppIconTile({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/images/app_icon.svg', width: size, height: size, excludeFromSemantics: true);
}
