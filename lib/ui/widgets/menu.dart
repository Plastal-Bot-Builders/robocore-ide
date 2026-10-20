// Drop-down menus: the rows (RcMenu) and a button that opens one under itself (MenuButton).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import '../../theme.dart';
import 'common.dart';
import 'popover.dart';

/// One row of a menu, or a divider ([MenuEntry.divider]).
class MenuEntry {
  const MenuEntry(this.label, {this.icon, required this.onTap}) : divider = false;
  const MenuEntry._divider()
      : label = '',
        icon = null,
        onTap = null,
        divider = true;
  static const MenuEntry line = MenuEntry._divider();

  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final bool divider;
}

/// A menu's rows. Picking one closes the menu ([onDone]) and then runs it; Esc closes it (G-15).
class RcMenu extends StatefulWidget {
  const RcMenu({super.key, required this.entries, required this.onDone, this.width = 200, this.header});
  final List<MenuEntry> entries;
  final VoidCallback onDone;
  final double width;
  final Widget? header;

  @override
  State<RcMenu> createState() => _RcMenuState();
}

class _RcMenuState extends State<RcMenu> {
  // Asked for outright: autofocus would do nothing while an editor still holds the focus.
  final _focus = FocusNode(debugLabel: 'Menu');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    Widget row(MenuEntry e) {
      if (e.divider) return Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: c.line2);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Hover(
          onTap: e.onTap == null
              ? null
              : () {
                  widget.onDone();
                  e.onTap!();
                },
          builder: (context, h) => Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: h ? c.sunk : Colors.transparent, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              if (e.icon != null) ...[RcIcon(e.icon!, size: 16, color: c.ink), const SizedBox(width: 10)],
              Expanded(child: Text(e.label, style: tLabel(c, w: FontWeight.w500), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      );
    }

    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onDone();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: c.raised,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(10),
          boxShadow: popShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.header != null) widget.header!,
          const SizedBox(height: 4),
          for (final e in widget.entries) row(e),
          const SizedBox(height: 4),
        ]),
      ),
    );
  }
}

/// [builder] draws the button (given whether the menu is open); a tap opens [entries] under it.
class MenuButton extends StatefulWidget {
  const MenuButton({super.key, required this.entries, required this.builder, this.width = 200, this.alignRight = true, this.header});
  final List<MenuEntry> Function() entries;
  final Widget Function(BuildContext context, bool open, VoidCallback toggle) builder;
  final double width;
  final bool alignRight;
  final Widget? header;

  @override
  State<MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<MenuButton> {
  bool open = false;

  void _close() {
    if (mounted && open) setState(() => open = false);
  }

  @override
  Widget build(BuildContext context) {
    return Popover(
      open: open,
      onClose: _close,
      alignRight: widget.alignRight,
      offset: 4,
      popup: (_) => RcMenu(entries: widget.entries(), onDone: _close, width: widget.width, header: widget.header),
      child: widget.builder(context, open, () => setState(() => open = !open)),
    );
  }
}
