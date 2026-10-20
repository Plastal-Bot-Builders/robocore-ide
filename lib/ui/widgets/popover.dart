import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import '../editor/web_editors.dart' show coverEditorFrames;

/// Shows [popup] under [child] while [open] is true. Tapping outside calls [onClose].
class Popover extends StatefulWidget {
  const Popover({
    super.key,
    required this.open,
    required this.onClose,
    required this.child,
    required this.popup,
    this.alignRight = true,
    this.offset = 6,
    this.escCloses = false,
  });
  final bool open;
  final VoidCallback onClose;
  final Widget child;
  final WidgetBuilder popup;
  final bool alignRight;
  final double offset;

  /// Esc closes it (G-15). The popup takes the keyboard focus for that, so leave it off when focus must
  /// stay in a field (search).
  final bool escCloses;

  @override
  State<Popover> createState() => _PopoverState();
}

class _PopoverState extends State<Popover> {
  final _link = LayerLink();
  final _ctl = OverlayPortalController();
  bool _covering = false;

  // A popup over Blockly or Monaco only gets its clicks while their iframes take none.
  void _cover(bool on) {
    if (on == _covering) return;
    _covering = on;
    coverEditorFrames(on);
  }

  @override
  void dispose() {
    _cover(false);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(Popover old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    if (widget.open && !_ctl.isShowing) _ctl.show();
    if (!widget.open && _ctl.isShowing) _ctl.hide();
    _cover(widget.open);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _ctl,
      overlayChildBuilder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: widget.onClose),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: widget.alignRight ? Alignment.bottomRight : Alignment.bottomLeft,
            followerAnchor: widget.alignRight ? Alignment.topRight : Alignment.topLeft,
            offset: Offset(0, widget.offset),
            child: Align(
              alignment: widget.alignRight ? Alignment.topRight : Alignment.topLeft,
              child: Material(
                type: MaterialType.transparency,
                child: widget.escCloses ? _EscCloses(onClose: widget.onClose, child: widget.popup(context)) : widget.popup(context),
              ),
            ),
          ),
        ],
      ),
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}

class _EscCloses extends StatefulWidget {
  const _EscCloses({required this.onClose, required this.child});
  final VoidCallback onClose;
  final Widget child;
  @override
  State<_EscCloses> createState() => _EscClosesState();
}

class _EscClosesState extends State<_EscCloses> {
  // Asked for outright: autofocus would do nothing while an editor still holds the focus.
  final _focus = FocusNode(debugLabel: 'Popover');

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
  Widget build(BuildContext context) => Focus(
        focusNode: _focus,
        onKeyEvent: (node, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: widget.child,
      );
}
