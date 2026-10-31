// Drop-down menus: the rows (RcMenu) and a button that opens one under itself (MenuButton).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;

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

/// A menu's rows. Picking one closes the menu ([onDone]) and then runs it; Esc closes it (G-15). The arrow keys move
/// between the rows, and the keyboard focus goes back where it was when the menu closes from the keyboard.
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
  final _back = FocusManager.instance.primaryFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  // Before the menu goes (and before a picked row runs, as it may open a dialog that takes the focus).
  void _done() {
    if (_back?.context?.mounted ?? false) _back!.requestFocus();
    widget.onDone();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape && e is KeyDownEvent) {
      _done();
      return KeyEventResult.handled;
    }
    final down = k == LogicalKeyboardKey.arrowDown, up = k == LogicalKeyboardKey.arrowUp;
    final ends = k == LogicalKeyboardKey.home || k == LogicalKeyboardKey.end;
    if (!down && !up && !ends) return KeyEventResult.ignored;
    final rows = _focus.traversalDescendants.toList();
    if (rows.isEmpty) return KeyEventResult.handled;
    final i = rows.indexWhere((n) => n.hasPrimaryFocus);
    final next = k == LogicalKeyboardKey.home
        ? 0
        : k == LogicalKeyboardKey.end
            ? rows.length - 1
            : down
                ? (i + 1) % rows.length
                : (i <= 0 ? rows.length - 1 : i - 1);
    rows[next].requestFocus();
    return KeyEventResult.handled;
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
      // A gap, not a line: the design has no dividers.
      if (e.divider) return const SizedBox(height: 9);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Hover(
          onTap: e.onTap == null
              ? null
              : () {
                  _done();
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
      onKeyEvent: _key,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: c.raised,
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
