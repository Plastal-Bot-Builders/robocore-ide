import 'package:flutter/material.dart';

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
  });
  final bool open;
  final VoidCallback onClose;
  final Widget child;
  final WidgetBuilder popup;
  final bool alignRight;
  final double offset;

  @override
  State<Popover> createState() => _PopoverState();
}

class _PopoverState extends State<Popover> {
  final _link = LayerLink();
  final _ctl = OverlayPortalController();

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
              child: Material(type: MaterialType.transparency, child: widget.popup(context)),
            ),
          ),
        ],
      ),
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}
