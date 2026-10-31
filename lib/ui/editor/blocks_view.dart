// Blocks workspace: categories, palette and the canvas with "on start" and
// "forever" stacks. Drag blocks in, reorder them, drop them on the palette
// to delete, or tap a palette block to add it to the selected stack.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../state/models.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

bool get _touchFirst => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// What is being dragged: a new block from the palette, or an existing one.
class BlockDrag {
  final String? newType;
  final String? stack;
  final int? index;
  const BlockDrag.palette(String t)
      : newType = t,
        stack = null,
        index = null;
  const BlockDrag.existing(String s, int i)
      : newType = null,
        stack = s,
        index = i;
  bool get fromPalette => newType != null;
}

Color _fill(String t) => (kBlockTypes[t]?.isControl ?? false) ? kBrand : kNavy;
Color _ink(String t) => (kBlockTypes[t]?.isControl ?? false) ? kNavy : kCream;

/// Puzzle-piece outline: notch cut into the top, tab hanging off the bottom.
class _BlockPainter extends CustomPainter {
  _BlockPainter(this.fill, {this.attached = false});
  final Color fill;
  final bool attached;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const r = 4.0;
    final lr = attached ? 0.0 : r;
    final p = Path()
      ..moveTo(lr, 0)
      ..lineTo(14, 0)
      ..lineTo(17, 5)
      ..lineTo(29, 5)
      ..lineTo(32, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(32, h)
      ..lineTo(28.8, h + 6)
      ..lineTo(17.2, h + 6)
      ..lineTo(14, h)
      ..lineTo(lr, h);
    if (lr > 0) {
      p
        ..quadraticBezierTo(0, h, 0, h - lr)
        ..lineTo(0, lr)
        ..quadraticBezierTo(0, 0, lr, 0);
    } else {
      p
        ..lineTo(0, h)
        ..lineTo(0, 0);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = fill);
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = kNavy);
  }

  @override
  bool shouldRepaint(_BlockPainter o) => o.fill != fill || o.attached != attached;
}

class BlocksView extends StatelessWidget {
  const BlocksView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final p = s.cur!;
    final phone = MediaQuery.sizeOf(context).width < 760;
    final cat = kCats.firstWhere((x) => x.id == s.cat, orElse: () => kCats.first);
    final types = kBlockTypes.entries.where((e) => e.value.cat == cat.id).map((e) => e.key).toList();

    final banner = p.codeEdited
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            color: c.brandSoft,
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
              RcIcon('info', size: 16, color: c.ink),
              Text(
                  '${p.setup.length + p.loop.length > 0 ? 'The code was edited by hand, so these blocks no longer match it.' : 'This project was written in code.'} Verify and Upload use the code.',
                  style: tBody(c, size: 13)),
              _RebuildButton(onConfirm: s.rebuildFromBlocks),
            ]),
          )
        : null;

    final palette = DragTarget<BlockDrag>(
      onWillAcceptWithDetails: (d) => !d.data.fromPalette,
      onAcceptWithDetails: (d) => s.removeBlock(d.data.stack!, d.data.index!),
      builder: (context, cand, _) => Container(
        color: cand.isNotEmpty ? c.errSoft : c.surface,
        child: phone
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Row(children: [
                  for (final t in types) Padding(padding: const EdgeInsets.only(right: 12), child: _PaletteBlock(type: t)),
                ]),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Text(cand.isNotEmpty ? 'DROP TO DELETE' : cat.name.toUpperCase(), style: tH2(c)),
                  const SizedBox(height: 14),
                  for (final t in types)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Align(alignment: Alignment.centerLeft, child: _PaletteBlock(type: t)),
                    ),
                ],
              ),
      ),
    );

    final cats = phone
        ? SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              children: [for (final k in kCats) _CatButton(k: k, on: k.id == cat.id, compact: true)],
            ),
          )
        : Container(
            width: 160,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            color: c.surface,
            child: ListView(children: [for (final k in kCats) _CatButton(k: k, on: k.id == cat.id)]),
          );

    final canvas = _Canvas(p: p);

    return Column(children: [
      if (banner != null) banner,
      Expanded(
        child: phone
            ? Column(children: [
                cats,
                SizedBox(height: 76, child: palette),
                Expanded(child: canvas),
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                cats,
                SizedBox(width: 280, child: palette),
                Expanded(child: canvas),
              ]),
      ),
    ]);
  }
}

class _RebuildButton extends StatefulWidget {
  const _RebuildButton({required this.onConfirm});
  final VoidCallback onConfirm;
  @override
  State<_RebuildButton> createState() => _RebuildButtonState();
}

class _RebuildButtonState extends State<_RebuildButton> {
  bool armed = false;
  @override
  Widget build(BuildContext context) => Btn(
        armed ? 'Click again to replace the code' : 'Replace code with these blocks',
        small: true,
        kind: armed ? BtnKind.primary : BtnKind.outline,
        onTap: () {
          if (!armed) return setState(() => armed = true);
          widget.onConfirm();
        },
      );
}

class _CatButton extends StatelessWidget {
  const _CatButton({required this.k, required this.on, this.compact = false});
  final BlockCat k;
  final bool on, compact;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    final c = RC.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 2, right: compact ? 6 : 0),
      child: Hover(
        onTap: () => s.setCat(k.id),
        builder: (context, h) => Container(
          height: 34,
          padding: const EdgeInsets.only(left: 12, right: 10),
          decoration: BoxDecoration(
            color: on ? c.brandSoft : (h ? c.sunk : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            if (on && !compact)
              Positioned(
                left: -12,
                top: 8,
                child: Container(
                  width: 3,
                  height: 18,
                  decoration: const BoxDecoration(color: kBrand, borderRadius: BorderRadius.horizontal(right: Radius.circular(2))),
                ),
              ),
            Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
              RcIcon(k.icon, size: 18, color: c.ink),
              const SizedBox(width: 10),
              Text(k.name, style: tLabel(c, color: on ? c.ink : c.muted, w: on ? FontWeight.w600 : FontWeight.w500)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// A block's contents (labels and fields).
class _BlockBody extends StatelessWidget {
  const _BlockBody({required this.type, required this.values, this.stack, this.index});
  final String type;
  final Map<String, dynamic> values;
  final String? stack;
  final int? index;
  bool get pal => stack == null;

  @override
  Widget build(BuildContext context) {
    final d = kBlockTypes[type]!;
    final ctl = d.isControl;
    final ink = _ink(type);
    final kids = <Widget>[];
    for (final part in d.parts) {
      if (kids.isNotEmpty) kids.add(const SizedBox(width: 8));
      if (part is String) {
        kids.add(Text(part,
            style: TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: ink)));
        continue;
      }
      final f = part as BField;
      final v = values[f.k] ?? d.def[f.k];
      if (f.type == 'sel') {
        // Pin lists depend on the board (on the RoboCore V2 only the free pins are offered).
        final board = AppScope.of(context).cur?.board ?? 'v2';
        final opts = f.k == 'pin' ? pinOptions(board, tone: type == 'tone') : f.opts;
        kids.add(_SelectPill(
          value: '$v',
          opts: opts,
          control: ctl,
          onChanged: pal ? null : (nv) => AppScope.read(context).setBlockField(stack!, index!, f.k, nv),
        ));
      } else {
        kids.add(_InputPill(
          key: ValueKey('$stack-$index-${f.k}'),
          value: _fmtVal(v),
          numeric: f.type == 'num',
          control: ctl,
          enabled: !pal,
          onChanged: (nv) {
            final dyn = f.type == 'num' ? (nv.isEmpty ? 0 : (num.tryParse(nv) ?? 0)) : nv;
            AppScope.read(context).setBlockField(stack!, index!, f.k, dyn, snapshot: false);
          },
          onFocus: () => AppScope.read(context).snap(),
        ));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: kids);
  }

  static String _fmtVal(dynamic v) {
    if (v is double && v == v.truncateToDouble()) return v.toInt().toString();
    return '$v';
  }
}

class _SelectPill extends StatelessWidget {
  const _SelectPill({required this.value, required this.opts, required this.control, this.onChanged});
  final String value;
  final List<String> opts;
  final bool control;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final bg = control ? kBrandPressed : kNavyHover;
    final fg = control ? kNavy : kCream;
    final pill = Container(
      height: 24,
      padding: const EdgeInsets.only(left: 8, right: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontFamily: fBody, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: fg)),
        const SizedBox(width: 4),
        RcIcon('chev', size: 12, color: fg),
      ]),
    );
    if (onChanged == null) return pill;
    return PopupMenuButton<String>(
      tooltip: '',
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      color: c.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (_) => [
        for (final o in opts)
          PopupMenuItem<String>(
            value: o,
            height: 32,
            child: Text(o, style: TextStyle(fontFamily: fBody, fontSize: 13, fontWeight: o == value ? FontWeight.w700 : FontWeight.w500, color: c.ink)),
          ),
      ],
      child: MouseRegion(cursor: SystemMouseCursors.click, child: pill),
    );
  }
}

class _InputPill extends StatefulWidget {
  const _InputPill({
    super.key,
    required this.value,
    required this.numeric,
    required this.control,
    required this.enabled,
    required this.onChanged,
    required this.onFocus,
  });
  final String value;
  final bool numeric, control, enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onFocus;

  @override
  State<_InputPill> createState() => _InputPillState();
}

class _InputPillState extends State<_InputPill> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (_f.hasFocus) widget.onFocus();
    });
  }

  @override
  void didUpdateWidget(_InputPill old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: fBody, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: kNavy);
    final tp = TextPainter(text: TextSpan(text: _c.text.isEmpty ? '0' : _c.text, style: style), textDirection: TextDirection.ltr)..layout();
    final w = (tp.width + 22).clamp(32.0, 220.0);
    final deco = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: widget.control ? Border.all(color: kNavy) : null,
    );
    if (!widget.enabled) {
      return Container(
        height: 24,
        constraints: const BoxConstraints(minWidth: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: deco,
        child: Text(widget.value, style: style),
      );
    }
    return Container(
      height: 24,
      width: w,
      alignment: Alignment.center,
      decoration: deco,
      child: TextField(
        controller: _c,
        focusNode: _f,
        textAlign: TextAlign.center,
        style: style,
        cursorColor: kNavy,
        cursorHeight: 14,
        keyboardType: widget.numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
      ),
    );
  }
}

/// A block drawn with the puzzle outline.
class BlockTile extends StatelessWidget {
  const BlockTile({super.key, required this.type, required this.values, this.stack, this.index, this.attached = false, this.dimmed = false});
  final String type;
  final Map<String, dynamic> values;
  final String? stack;
  final int? index;
  final bool attached, dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? .4 : 1,
      child: CustomPaint(
        painter: _BlockPainter(_fill(type), attached: attached),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _BlockBody(type: type, values: values, stack: stack, index: index),
        ),
      ),
    );
  }
}

class _PaletteBlock extends StatelessWidget {
  const _PaletteBlock({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    final def = kBlockTypes[type]!.def;
    final tile = BlockTile(type: type, values: def);
    final fb = Material(color: Colors.transparent, child: tile);
    final target = s.target == 'setup' ? 'on start' : 'forever';
    final child = Hover(onTap: () => s.addBlock(type), tooltip: 'Click to add to $target', builder: (context, h) => tile);
    return _touchFirst
        ? LongPressDraggable<BlockDrag>(
            data: BlockDrag.palette(type),
            feedback: fb,
            childWhenDragging: Opacity(opacity: .4, child: tile),
            child: child)
        : Draggable<BlockDrag>(
            data: BlockDrag.palette(type),
            feedback: fb,
            childWhenDragging: Opacity(opacity: .4, child: tile),
            child: child);
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({required this.p});
  final Project p;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;
    return Container(
      color: c.surface,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _DotGrid(c.line))),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: phone ? const EdgeInsets.fromLTRB(20, 24, 20, 80) : const EdgeInsets.fromLTRB(48, 40, 48, 80),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Transform.scale(
                scale: s.zoom,
                alignment: Alignment.topLeft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _StackView(p: p, stack: 'setup'),
                  const SizedBox(height: 36),
                  _StackView(p: p, stack: 'loop'),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Color(0x1A1B2A41), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconBtn('zout', onTap: () => s.setZoom(-1), tip: 'Zoom out'),
              IconBtn('fit', onTap: () => s.setZoom(0), tip: 'Reset zoom'),
              IconBtn('zin', onTap: () => s.setZoom(1), tip: 'Zoom in'),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _DotGrid extends CustomPainter {
  _DotGrid(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 12; y < size.height; y += 24) {
      for (double x = 12; x < size.width; x += 24) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGrid o) => o.color != color;
}

/// The yellow C-shaped container ("on start" / "forever") holding a list of blocks.
class _StackView extends StatelessWidget {
  const _StackView({required this.p, required this.stack});
  final Project p;
  final String stack;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final list = p.stack(stack);
    final isTarget = s.target == stack;

    final hat = GestureDetector(
      onTap: () => s.setTarget(stack),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: 'New blocks go here',
          waitDuration: const Duration(milliseconds: 600),
          child: CustomPaint(
            painter: _HatPainter(selected: isTarget),
            child: Container(
              width: 150,
              height: 58,
              padding: const EdgeInsets.only(left: 12, top: 18),
              alignment: Alignment.centerLeft,
              child: Text(stack == 'setup' ? 'on start' : 'forever',
                  style: const TextStyle(fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: kNavy)),
            ),
          ),
        ),
      ),
    );

    final rows = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      rows.add(_DropZone(stack: stack, index: i, child: _StackBlock(b: list[i], stack: stack, index: i)));
    }
    rows.add(_DropZone(
      stack: stack,
      index: list.length,
      child: list.isEmpty
          ? Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              constraints: const BoxConstraints(minWidth: 200),
              decoration: BoxDecoration(
                color: c.sunk,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('Drop or click blocks to add them here', style: tCaption(c, color: c.faint)),
            )
          : const SizedBox(width: 200, height: 10),
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      hat,
      // the arm: navy outline + 19px of yellow on the left
      Container(
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: kNavy, width: 1))),
        child: Container(
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: kBrand, width: 19))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
        ),
      ),
      Container(
        width: 150,
        height: 24,
        decoration: BoxDecoration(
          color: kBrand,
          border: Border.all(color: kNavy),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6), topRight: Radius.circular(6)),
        ),
      ),
    ]);
  }
}

class _HatPainter extends CustomPainter {
  _HatPainter({required this.selected});
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    // dome (96 x 30) on top of a 150 x 40 header; the header ends 18px down.
    const top = 18.0;
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(0, top + 8)
      ..cubicTo(0, -2, 96, -2, 96, top)
      ..lineTo(w - 6, top)
      ..quadraticBezierTo(w, top, w, top + 6)
      ..lineTo(w, h)
      ..lineTo(32, h)
      ..lineTo(29, h + 5)
      ..lineTo(17, h + 5)
      ..lineTo(14, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p, Paint()..color = kBrand);
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = kNavy);
  }

  @override
  bool shouldRepaint(_HatPainter o) => o.selected != selected;
}

class _StackBlock extends StatelessWidget {
  const _StackBlock({required this.b, required this.stack, required this.index});
  final Block b;
  final String stack;
  final int index;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    final t = b['t'] as String;
    final tile = BlockTile(type: t, values: b, stack: stack, index: index, attached: true);
    final feedback = Material(color: Colors.transparent, child: BlockTile(type: t, values: b));
    final withDelete = _Deletable(onDelete: () => s.removeBlock(stack, index), dark: !kBlockTypes[t]!.isControl, child: tile);
    final data = BlockDrag.existing(stack, index);
    return _touchFirst
        ? LongPressDraggable<BlockDrag>(data: data, feedback: feedback, childWhenDragging: Opacity(opacity: .35, child: tile), child: withDelete)
        : Draggable<BlockDrag>(data: data, feedback: feedback, childWhenDragging: Opacity(opacity: .35, child: tile), child: withDelete);
  }
}

class _Deletable extends StatefulWidget {
  const _Deletable({required this.child, required this.onDelete, required this.dark});
  final Widget child;
  final VoidCallback onDelete;
  final bool dark;
  @override
  State<_Deletable> createState() => _DeletableState();
}

class _DeletableState extends State<_Deletable> {
  bool h = false;
  @override
  Widget build(BuildContext context) {
    final show = h || _touchFirst;
    return MouseRegion(
      onEnter: (_) => setState(() => h = true),
      onExit: (_) => setState(() => h = false),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        widget.child,
        const SizedBox(width: 4),
        AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: IgnorePointer(
            ignoring: !show,
            child: IconBtn('x', onTap: widget.onDelete, tip: 'Remove block', size: 22, iconSize: 12),
          ),
        ),
      ]),
    );
  }
}

/// Accepts a dragged block and inserts it before [index] in [stack].
class _DropZone extends StatelessWidget {
  const _DropZone({required this.stack, required this.index, required this.child});
  final String stack;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    return DragTarget<BlockDrag>(
      onWillAcceptWithDetails: (d) => !(d.data.stack == stack && (d.data.index == index)),
      onAcceptWithDetails: (d) {
        final b = d.data;
        if (b.fromPalette) {
          s.addBlock(b.newType!, stack: stack, index: index);
        } else {
          s.moveBlock(b.stack!, b.index!, stack, index);
        }
      },
      builder: (context, cand, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: cand.isEmpty ? 0 : 4,
          width: 180,
          margin: EdgeInsets.only(bottom: cand.isEmpty ? 0 : 3),
          decoration: BoxDecoration(color: kNavy, borderRadius: BorderRadius.circular(2)),
        ),
        child,
      ]),
    );
  }
}
