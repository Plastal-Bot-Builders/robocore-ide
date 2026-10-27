// A drag handle between two panes (blocks ⇄ C++, editor ⇄ console). Press and drag it to resize the panes;
// double-click it to go back to the default size.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../editor/web_editors.dart' show setEditorFramesInteractive;

class SplitHandle extends StatefulWidget {
  const SplitHandle({
    super.key,
    required this.axis,
    required this.thickness,
    required this.onDrag,
    this.onEnd,
    this.onReset,
    this.line = false,
    this.tip = 'Drag to resize. Double-click to reset.',
  });

  /// [Axis.horizontal]: the panes sit side by side and the handle is dragged left and right.
  final Axis axis;
  final double thickness;

  /// Called with the pointer movement along [axis], in logical pixels.
  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd, onReset;

  /// Draw a divider line along the handle (otherwise only a grip shows on hover).
  final bool line;
  final String tip;

  @override
  State<SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<SplitHandle> {
  bool _hover = false, _drag = false;

  bool get _sideways => widget.axis == Axis.horizontal;

  void _start() => setState(() => _drag = true);

  void _end() {
    setState(() => _drag = false);
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final on = _hover || _drag;
    final Widget mark;
    if (widget.line) {
      mark = AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: _sideways ? (on ? 3 : 1) : null,
        height: _sideways ? null : (on ? 3 : 1),
        color: on ? kBrand : c.line2,
      );
    } else {
      mark = AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: on ? 1 : 0,
        child: Container(
          width: _sideways ? 4 : 40,
          height: _sideways ? 40 : 4,
          decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(2)),
        ),
      );
    }
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 900),
      child: MouseRegion(
        cursor: _sideways ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        // The Blockly and Monaco iframes take the pointer as soon as it crosses them, before a drag is
        // even recognised, so they ignore it from the moment the button goes down on the handle.
        child: Listener(
          onPointerDown: (_) => setEditorFramesInteractive(false),
          onPointerUp: (_) => setEditorFramesInteractive(true),
          onPointerCancel: (_) => setEditorFramesInteractive(true),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A press and drag only: Flutter would also take a two-finger trackpad scroll over the handle as a drag
            // (a click-and-drag on a trackpad comes as a mouse).
            supportedDevices: const {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
            onDoubleTap: widget.onReset,
            onHorizontalDragStart: _sideways ? (_) => _start() : null,
            onHorizontalDragUpdate: _sideways ? (d) => widget.onDrag(d.delta.dx) : null,
            onHorizontalDragEnd: _sideways ? (_) => _end() : null,
            onHorizontalDragCancel: _sideways ? _end : null,
            onVerticalDragStart: _sideways ? null : (_) => _start(),
            onVerticalDragUpdate: _sideways ? null : (d) => widget.onDrag(d.delta.dy),
            onVerticalDragEnd: _sideways ? null : (_) => _end(),
            onVerticalDragCancel: _sideways ? null : _end,
            child: SizedBox(
              width: _sideways ? widget.thickness : double.infinity,
              height: _sideways ? double.infinity : widget.thickness,
              child: Center(child: mark),
            ),
          ),
        ),
      ),
    );
  }
}
