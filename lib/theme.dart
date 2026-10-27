// RoboCore design tokens (Figma rc-*), Paper and Navy themes.
import 'package:flutter/material.dart';

const fBody = 'Barlow';
const fDisplay = 'BarlowCondensed';
const fMono = 'JetBrainsMono';

/// For the arrows, ✓ and ⌘ that Barlow and JetBrains Mono lack (pubspec.yaml), so the web app never fetches them.
const kSymbolFonts = ['NotoSansMath', 'NotoSansSymbols2'];

const kBrand = Color(0xFFF2B01E);
const kBrandPressed = Color(0xFFD99A0F);
const kNavy = Color(0xFF1B2A41);
const kNavyHover = Color(0xFF364357);
const kCream = Color(0xFFF7F1E3);

@immutable
class RC extends ThemeExtension<RC> {
  final Color bg, surface, raised, sunk, ink, muted, faint, line, line2;

  /// The edge of a control (a field, a switch that is off, a radio): 3:1 against what is around it, which [line] is not.
  final Color field;

  /// The keyboard-focus ring: navy on paper, the box yellow on navy (WCAG 3:1 either way).
  final Color focus;
  final Color brandSoft, brandTint, top, topInk, topLine;
  final Color ok, okSoft, err, errSoft, warn, codeBg, sel;
  final Color sCom, sStr, sKw, sNum, sFn, sPre, sPlain, sLn, curLine, disabled, textBrand;
  final bool dark;

  const RC({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.sunk,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.line2,
    required this.field,
    required this.focus,
    required this.brandSoft,
    required this.brandTint,
    required this.top,
    required this.topInk,
    required this.topLine,
    required this.ok,
    required this.okSoft,
    required this.err,
    required this.errSoft,
    required this.warn,
    required this.codeBg,
    required this.sel,
    required this.sCom,
    required this.sStr,
    required this.sKw,
    required this.sNum,
    required this.sFn,
    required this.sPre,
    required this.sPlain,
    required this.sLn,
    required this.curLine,
    required this.disabled,
    required this.textBrand,
    required this.dark,
  });

  static const paper = RC(
    bg: Color(0xFFF7F1E3),
    surface: Color(0xFFFFFCF5),
    raised: Color(0xFFFFFFFF),
    sunk: Color(0xFFF0EDE7),
    ink: Color(0xFF1B2A41),
    muted: Color(0xFF5B6573),
    // faint, field and sLn are darker than the design's, which fell short of WCAG's contrast (4.5:1 text, 3:1 controls).
    faint: Color(0xFF5E6774),
    line: Color(0xFFDBDBD8),
    line2: Color(0xFFE7E5E0),
    field: Color(0xFF80868E),
    focus: Color(0xFF1B2A41),
    brandSoft: Color(0xFFFCE9BF),
    brandTint: Color(0xFFFDF1D5),
    top: Color(0xFFF2B01E),
    topInk: Color(0xFF1B2A41),
    topLine: Color(0x381B2A41),
    // The design has no green or red: success and "connected" are the ink colour, errors stand out by weight,
    // an icon or an inverted line, busy is the box yellow.
    ok: Color(0xFF1B2A41),
    okSoft: Color(0xFFF0EDE7),
    err: Color(0xFF1B2A41),
    errSoft: Color(0xFFFCE9BF),
    warn: Color(0xFF8F5F00),
    codeBg: Color(0xFFFFFFFF),
    sel: Color(0x52F2B01E),
    sCom: Color(0xFF6A7380),
    sStr: Color(0xFF8A5A00),
    sKw: Color(0xFF1B2A41),
    sNum: Color(0xFF8A5A00),
    sFn: Color(0xFF1B2A41),
    sPre: Color(0xFF8A5A00),
    sPlain: Color(0xFF364357),
    sLn: Color(0xFF6A7380),
    curLine: Color(0xFFFDF1D5),
    disabled: Color(0xFFA4A8AD),
    textBrand: Color(0xFF8A5A00),
    dark: false,
  );

  static const navy = RC(
    bg: Color(0xFF0F1828),
    surface: Color(0xFF152036),
    raised: Color(0xFF1B2A41),
    sunk: Color(0xFF111C30),
    ink: Color(0xFFF7F1E3),
    muted: Color(0xFFAEB5C0),
    faint: Color(0xFF9AA2AD),
    line: Color(0xFF2C3C57),
    line2: Color(0xFF233249),
    field: Color(0xFF717A8C),
    focus: Color(0xFFF2B01E),
    brandSoft: Color(0xFF3B3220),
    brandTint: Color(0xFF2A2617),
    top: Color(0xFFF2B01E),
    topInk: Color(0xFF1B2A41),
    topLine: Color(0x381B2A41),
    ok: Color(0xFFF7F1E3),
    okSoft: Color(0xFF111C30),
    err: Color(0xFFF7F1E3),
    errSoft: Color(0xFF3B3220),
    warn: Color(0xFFE8B04B),
    codeBg: Color(0xFF111C30),
    sel: Color(0x47F2B01E),
    sCom: Color(0xFF7E8794),
    sStr: Color(0xFF80D4A3),
    sKw: Color(0xFFC79DF3),
    sNum: Color(0xFFF4B274),
    sFn: Color(0xFF84B6FF),
    sPre: Color(0xFFF08CB2),
    sPlain: Color(0xFFC9CFD8),
    sLn: Color(0xFF8A93A0),
    curLine: Color(0xFF2A2617),
    disabled: Color(0xFF6B7486),
    textBrand: Color(0xFFE8B04B),
    dark: true,
  );

  static RC of(BuildContext context) => Theme.of(context).extension<RC>() ?? paper;

  @override
  RC copyWith() => this;

  @override
  RC lerp(ThemeExtension<RC>? other, double t) => (other is RC && t > .5) ? other : this;
}

ThemeData buildTheme(RC c) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: c.dark ? Brightness.dark : Brightness.light,
    fontFamily: fBody,
    fontFamilyFallback: kSymbolFonts,
    // The design's sizes everywhere: on desktops Flutter would otherwise shrink fields and menus ("compact"), so a
    // text field came out 8 px shorter than the button beside it on the Mac.
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kBrand,
      brightness: c.dark ? Brightness.dark : Brightness.light,
      primary: kNavy,
      surface: c.surface,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.ink.withValues(alpha: .04),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.ink, selectionColor: c.sel),
    tooltipTheme: TooltipThemeData(
      // The design's Tooltip: a 26 px navy pill, Label/Default text (13 px Medium).
      decoration: BoxDecoration(color: kNavy, borderRadius: BorderRadius.circular(4)),
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontFamily: fBody, fontSize: 13, fontWeight: FontWeight.w500, color: kCream, height: 16 / 13),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
  return base.copyWith(extensions: [c]);
}

// ---------- text styles ----------
TextStyle tBody(RC c, {double size = 14, FontWeight w = FontWeight.w400, Color? color, double? height}) =>
    TextStyle(fontFamily: fBody, fontSize: size, fontWeight: w, color: color ?? c.ink, height: height ?? (20 / 14));

TextStyle tH1(RC c) => TextStyle(
    fontFamily: fDisplay, fontSize: 26, height: 32 / 26, fontWeight: FontWeight.w700, letterSpacing: .26, color: c.ink);

TextStyle tH2(RC c) => TextStyle(
    fontFamily: fDisplay, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, letterSpacing: .54, color: c.ink);

TextStyle tOverline(RC c, {Color? color}) => TextStyle(
    fontFamily: fBody, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: .96, color: color ?? c.muted);

TextStyle tLabel(RC c, {Color? color, FontWeight w = FontWeight.w600}) =>
    TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: w, color: color ?? c.ink);

TextStyle tCaption(RC c, {Color? color, FontWeight w = FontWeight.w400}) =>
    TextStyle(fontFamily: fBody, fontSize: 12, height: 16 / 12, fontWeight: w, color: color ?? c.muted);

TextStyle tMono(RC c, {double size = 13, Color? color, FontWeight w = FontWeight.w400, double? height}) =>
    TextStyle(fontFamily: fMono, fontSize: size, height: height ?? (20 / 13), fontWeight: w, color: color ?? c.ink);

const popShadow = [
  BoxShadow(color: Color(0x1A1B2A41), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x241B2A41), blurRadius: 28, offset: Offset(0, 10)),
];
const modalShadow = [BoxShadow(color: Color(0x381B2A41), blurRadius: 56, offset: Offset(0, 20))];
