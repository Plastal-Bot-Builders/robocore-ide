// Shared building blocks: icons, buttons, inputs, selects, switches, cards.
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme.dart';
import 'icon_paths.dart';

/// The shortcut key: Cmd on a Mac (and iPad), Ctrl elsewhere. Spelled out: Barlow has no ⌘ glyph.
String get kMod => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS ? 'Cmd' : 'Ctrl';

class RcIcon extends StatelessWidget {
  const RcIcon(this.name, {super.key, this.size = 16, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? RC.of(context).ink;
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
        'stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${kIconPaths[name] ?? ''}</svg>';
    return SvgPicture.string(svg, width: size, height: size, colorFilter: ColorFilter.mode(c, BlendMode.srcIn));
  }
}

/// Pointer-hover aware wrapper used by most clickable things. It takes the keyboard focus too: Tab reaches it,
/// Enter or Space presses it, and a ring shows where the focus is (WCAG 2.1.1, 2.4.7). [radius] is the ring's.
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.onTap, this.cursor = SystemMouseCursors.click, this.tooltip, this.radius = 6});
  final Widget Function(BuildContext context, bool hover) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;
  final String? tooltip;
  final double radius;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _h = false, _ring = false;

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onTap?.call()),
  };

  @override
  Widget build(BuildContext context) {
    // A focused one looks hovered as well, so a menu row shows its highlight under the keyboard too. The ring sits
    // just outside, so it shows on a navy button too; the Stack stays when it goes, so the button keeps its state.
    Widget w = Stack(fit: StackFit.passthrough, clipBehavior: Clip.none, children: [
      widget.builder(context, _h || _ring),
      if (_ring)
        Positioned(
          left: -3,
          top: -3,
          right: -3,
          bottom: -3,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: FocusRing.of(context), width: 2),
                borderRadius: BorderRadius.circular(widget.radius + 3),
              ),
            ),
          ),
        ),
    ]);
    w = FocusableActionDetector(
      enabled: widget.onTap != null,
      actions: _actions,
      mouseCursor: MouseCursor.defer,
      onShowFocusHighlight: (v) => setState(() => _ring = v),
      child: MouseRegion(
        cursor: widget.onTap == null ? SystemMouseCursors.basic : widget.cursor,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: w,
        ),
      ),
    );
    if (widget.tooltip != null) w = tipped(widget.tooltip!, w);
    return Semantics(button: widget.onTap != null, label: widget.tooltip, child: w);
  }
}

/// The keyboard-focus ring's colour for the controls under it. The top bar is yellow in both themes, so it asks
/// for navy there; elsewhere it is the theme's [RC.focus].
class FocusRing extends InheritedWidget {
  const FocusRing({super.key, required this.color, required super.child});
  final Color color;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FocusRing>()?.color ?? RC.of(context).focus;

  @override
  bool updateShouldNotify(FocusRing old) => color != old.color;
}

final _shortcutTip = RegExp(r'^(.+) \(((?:Cmd|Ctrl)[^()]*)\)$');

/// A tooltip as the design draws it: "Verify (Cmd+R)" shows the label, then the shortcut faint after it.
Widget tipped(String tip, Widget child) {
  final m = _shortcutTip.firstMatch(tip);
  if (m == null) return Tooltip(message: tip, child: child);
  return Tooltip(
    richMessage: TextSpan(children: [
      TextSpan(text: m[1]),
      const WidgetSpan(child: SizedBox(width: 8)),
      TextSpan(text: m[2], style: TextStyle(fontSize: 12, color: kCream.withValues(alpha: .7))),
    ]),
    child: child,
  );
}

// Primary (navy), outline (the design's Secondary), plain (Ghost), and the outline on the yellow top bar.
// There is no red "danger" button in the design: Reset is Secondary, Delete project is Ghost with a trash icon.
enum BtnKind { primary, outline, plain, ghostTop }

class Btn extends StatelessWidget {
  const Btn(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.kind = BtnKind.outline,
    this.height = 32,
    this.small = false,
    this.expand = false,
    this.tooltip,
    this.busy = false,
  });
  final String label;
  final String? icon;
  final String? tooltip;
  final VoidCallback? onTap;
  final BtnKind kind;
  final double height;
  final bool small, expand;

  /// Working (Verifying…, Installing…): a turning loader instead of the icon, and not dimmed.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Hover(
      onTap: onTap,
      tooltip: tooltip,
      builder: (context, h) {
        Color bg, fg, border;
        switch (kind) {
          case BtnKind.primary:
            bg = c.dark ? kBrand : kNavy;
            fg = c.dark ? kNavy : kCream;
            border = bg;
            if (h) bg = c.dark ? kBrandPressed : kNavyHover;
            break;
          case BtnKind.outline:
            bg = h ? c.sunk : Colors.transparent;
            fg = c.ink;
            border = c.ink;
            break;
          case BtnKind.plain:
            bg = h ? c.sunk : Colors.transparent;
            fg = c.ink;
            border = Colors.transparent;
            break;
          case BtnKind.ghostTop:
            bg = h ? Colors.white.withValues(alpha: .35) : Colors.transparent;
            fg = kNavy;
            border = kNavy;
            break;
        }
        if (onTap == null && !busy) {
          fg = fg.withValues(alpha: .45);
          border = border.withValues(alpha: .3);
        }
        final hh = small ? 28.0 : height;
        return Container(
          height: hh,
          padding: EdgeInsets.only(left: small ? 10 : 12, right: small ? 10 : 14),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                ...[Spinner(size: 16, color: fg), const SizedBox(width: 8)]
              else if (icon != null)
                ...[RcIcon(icon!, size: 16, color: fg), const SizedBox(width: 8)],
              Text(label,
                  style: TextStyle(
                      fontFamily: fBody, fontSize: small ? 12.5 : 13, height: 16 / 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        );
      },
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, {super.key, this.onTap, this.tip, this.size = 32, this.iconSize = 18, this.color, this.active = false});
  final String icon;
  final VoidCallback? onTap;
  final String? tip;
  final double size, iconSize;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Hover(
      onTap: onTap,
      tooltip: tip,
      builder: (context, h) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.brandSoft : (h ? c.ink.withValues(alpha: .06) : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: RcIcon(icon, size: iconSize, color: (color ?? c.ink).withValues(alpha: onTap == null ? .4 : 1)),
      ),
    );
  }
}

class RcCard extends StatelessWidget {
  const RcCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.radius = 10, this.color, this.clip = true});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class RcSwitch extends StatelessWidget {
  const RcSwitch({super.key, required this.value, required this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Semantics(
      toggled: value,
      label: label,
      child: Hover(
        onTap: () => onChanged(!value),
        builder: (context, h) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 20,
          padding: const EdgeInsets.all(2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? (c.dark ? kBrand : kNavy) : c.field,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class RcInput extends StatelessWidget {
  const RcInput({
    super.key,
    this.controller,
    this.hint,
    this.icon,
    this.height = 32,
    this.onChanged,
    this.onSubmitted,
    this.fontSize = 13,
    this.focusNode,
    this.autofocus = false,
    this.error = false,
    this.trailing,
  });
  final TextEditingController? controller;
  final String? hint, icon;
  final double height, fontSize;
  final ValueChanged<String>? onChanged, onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus, error;

  /// A button inside the field, on the right (Cog's send).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    // An error keeps the ink border (1.5 px) and shows a warning icon in the field; the message under it is bold.
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: error ? BorderSide(color: c.ink, width: 1.5) : BorderSide(color: c.field),
    );
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        cursorColor: c.ink,
        cursorHeight: fontSize + 3,
        style: TextStyle(fontFamily: fBody, fontSize: fontSize, height: 18 / 13, color: c.ink),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.dark ? c.sunk : Colors.white,
          hintText: hint,
          hintStyle: TextStyle(fontFamily: fBody, fontSize: fontSize, color: c.faint),
          contentPadding: EdgeInsets.symmetric(horizontal: icon != null ? 0 : 12, vertical: (height - 18) / 2),
          prefixIcon: icon == null ? null : Padding(padding: const EdgeInsets.only(left: 10, right: 8), child: RcIcon(icon!, size: 16, color: c.ink)),
          prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 16),
          suffixIcon: error
              ? Padding(padding: const EdgeInsets.only(right: 10), child: RcIcon('alert', size: 16, color: c.ink))
              : (trailing == null ? null : Padding(padding: const EdgeInsets.only(right: 4), child: trailing)),
          suffixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 16),
          enabledBorder: border,
          border: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.ink, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// A compact dropdown styled like the Figma selects (border, chevron, 6px radius).
/// A select as in the design: white field with a chevron; while open, an ink border and an up chevron. In the menu the
/// chosen option has a yellow row, bold text and a check.
class RcSelect<T> extends StatefulWidget {
  const RcSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.height = 32,
    this.label,
  });
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double? width;
  final double height;
  final String? label;

  @override
  State<RcSelect<T>> createState() => _RcSelectState<T>();
}

class _RcSelectState<T> extends State<RcSelect<T>> {
  bool _open = false;

  void _set(bool v) {
    if (mounted && _open != v) setState(() => _open = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final w = widget;
    final current = w.items.where((e) => e.$1 == w.value).map((e) => e.$2).firstOrNull ?? '${w.value}';
    return Semantics(
      label: w.label,
      child: PopupMenuButton<T>(
        tooltip: '',
        initialValue: w.value,
        onOpened: () => _set(true),
        onCanceled: () => _set(false),
        onSelected: (v) {
          _set(false);
          w.onChanged(v);
        },
        position: PopupMenuPosition.under,
        color: c.raised,
        elevation: 6,
        menuPadding: const EdgeInsets.all(4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.line)),
        constraints: BoxConstraints(minWidth: (w.width != null && w.width!.isFinite) ? w.width! : 160),
        itemBuilder: (_) => [
          for (final it in w.items)
            PopupMenuItem<T>(
              value: it.$1,
              height: 33,
              padding: EdgeInsets.zero,
              child: Container(
                height: 33,
                padding: const EdgeInsets.only(left: 10, right: 8),
                decoration: BoxDecoration(
                  color: it.$1 == w.value ? (c.dark ? kBrand.withValues(alpha: .2) : c.brandSoft) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(it.$2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: fBody, fontSize: 13, fontWeight: it.$1 == w.value ? FontWeight.w600 : FontWeight.w500, color: c.ink)),
                  ),
                  if (it.$1 == w.value) ...[const SizedBox(width: 8), RcIcon('check', size: 16, color: c.ink)],
                ]),
              ),
            ),
        ],
        child: Container(
          width: w.width,
          height: w.height,
          padding: const EdgeInsets.only(left: 10, right: 8),
          decoration: BoxDecoration(
            color: c.dark ? c.sunk : Colors.white,
            border: _open ? Border.all(color: c.ink, width: 1.5) : Border.all(color: c.field),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: w.width == null ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Flexible(
                fit: w.width == null ? FlexFit.loose : FlexFit.tight,
                child: Text(current,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w500, color: c.ink)),
              ),
              const SizedBox(width: 8),
              RotatedBox(quarterTurns: _open ? 2 : 0, child: RcIcon('chev', size: 16, color: c.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(), style: tH1(c)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: tBody(c, color: c.muted)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ],
    );
  }
}

/// Filter pill row (All / Blocks / Code, example categories).
class Pills extends StatelessWidget {
  const Pills({super.key, required this.items, required this.value, required this.onChanged});
  final List<(String, String)> items;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          Hover(
            onTap: () => onChanged(it.$1),
            builder: (context, h) {
              final on = it.$1 == value;
              return Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: on ? c.ink : (h ? c.sunk : Colors.transparent),
                  border: Border.all(color: on ? c.ink : c.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(it.$2,
                      style: TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w500, color: on ? c.bg : c.ink)),
                ),
              );
            },
          ),
      ],
    );
  }
}

class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.bg, this.fg});
  final String text;
  final Color? bg, fg;
  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg ?? c.sunk, borderRadius: BorderRadius.circular(4)),
      child: Center(
        widthFactor: 1,
        child: Text(text, style: TextStyle(fontFamily: fBody, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: fg ?? c.ink)),
      ),
    );
  }
}

/// The design's loader icon, turning: Verifying…, Uploading…, Installing…, Testing….
class Spinner extends StatefulWidget {
  const Spinner({super.key, this.size = 16, required this.color});
  final double size;
  final Color color;
  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _turn, child: RcIcon('loader', size: widget.size, color: widget.color));
}

/// A status dot: filled = connected / done, [ring] = not connected (the design's Connection Status).
class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 8, this.ring = false});
  final Color color;
  final double size;
  final bool ring;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: ring
            ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.5))
            : BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The connection dot: filled ink when connected, an ink ring when not.
class LinkDot extends StatelessWidget {
  const LinkDot({super.key, required this.on, this.size = 8});
  final bool on;
  final double size;
  @override
  Widget build(BuildContext context) => Dot(color: RC.of(context).ink, size: size, ring: !on);
}

class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, this.onTap});
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final arrow = text.endsWith(' →');
    final label = arrow ? text.substring(0, text.length - 2) : text;
    return Hover(
      onTap: onTap,
      builder: (context, h) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
              fontFamily: fBody,
              fontSize: 13,
              height: 16 / 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
              decoration: h ? TextDecoration.underline : TextDecoration.none,
            )),
        if (arrow) ...[const SizedBox(width: 4), RcIcon('arrow', size: 14, color: c.ink)],
      ]),
    );
  }
}
