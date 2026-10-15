// Shared building blocks: icons, buttons, inputs, selects, switches, cards.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme.dart';
import 'icon_paths.dart';

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

/// Pointer-hover aware wrapper used by most clickable things.
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.onTap, this.cursor = SystemMouseCursors.click, this.tooltip});
  final Widget Function(BuildContext context, bool hover) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;
  final String? tooltip;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    Widget w = MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : widget.cursor,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _h),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return Semantics(button: widget.onTap != null, label: widget.tooltip, child: w);
  }
}

enum BtnKind { primary, outline, plain, ghostTop, danger }

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
  });
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final double height;
  final bool small, expand;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Hover(
      onTap: onTap,
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
          case BtnKind.danger:
            bg = h ? c.errSoft : Colors.transparent;
            fg = c.err;
            border = c.err;
            break;
        }
        if (onTap == null) {
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
              if (icon != null) ...[RcIcon(icon!, size: 16, color: fg), const SizedBox(width: 8)],
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
            color: value ? (c.dark ? kBrand : kNavy) : (c.dark ? c.line : const Color(0xFFDBDBD8)),
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
  });
  final TextEditingController? controller;
  final String? hint, icon;
  final double height, fontSize;
  final ValueChanged<String>? onChanged, onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus, error;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: error ? c.err : c.line),
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
          enabledBorder: border,
          border: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: error ? c.err : c.ink, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// A compact dropdown styled like the Figma selects (border, chevron, 6px radius).
class RcSelect<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final current = items.where((e) => e.$1 == value).map((e) => e.$2).firstOrNull ?? '$value';
    return Semantics(
      label: label,
      child: PopupMenuButton<T>(
        tooltip: '',
        initialValue: value,
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        color: c.raised,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.line)),
        constraints: BoxConstraints(minWidth: (width != null && width!.isFinite) ? width! : 160),
        itemBuilder: (_) => [
          for (final it in items)
            PopupMenuItem<T>(
              value: it.$1,
              height: 34,
              child: Text(it.$2,
                  style: TextStyle(
                      fontFamily: fBody,
                      fontSize: 13,
                      fontWeight: it.$1 == value ? FontWeight.w600 : FontWeight.w500,
                      color: c.ink)),
            ),
        ],
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.only(left: 10, right: 8),
          decoration: BoxDecoration(
            color: c.dark ? c.sunk : Colors.white,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Flexible(
                fit: width == null ? FlexFit.loose : FlexFit.tight,
                child: Text(current,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w500, color: c.ink)),
              ),
              const SizedBox(width: 8),
              RcIcon('chev', size: 16, color: c.ink),
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
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? c.ink : (h ? c.sunk : Colors.transparent),
                  border: Border.all(color: on ? c.ink : c.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(it.$2,
                    style: TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w500, color: on ? c.bg : c.ink)),
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
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg ?? c.sunk, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontFamily: fBody, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: fg ?? c.ink)),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, this.onTap});
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Hover(
      onTap: onTap,
      builder: (context, h) => Text(text,
          style: TextStyle(
            fontFamily: fBody,
            fontSize: 13,
            height: 16 / 13,
            fontWeight: FontWeight.w600,
            color: c.ink,
            decoration: h ? TextDecoration.underline : TextDecoration.none,
          )),
    );
  }
}
