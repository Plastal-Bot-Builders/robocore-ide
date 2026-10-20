// Project card with its mini preview, and the board summary card.
import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../state/app_state.dart';
import '../../state/models.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../dialogs.dart';
import 'common.dart';
import 'menu.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.p});
  final Project p;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    final c = RC.of(context);
    return Hover(
      onTap: () => s.openProject(p.id),
      builder: (context, h) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: h ? c.faint : c.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 112, child: Thumb(blocks: p.mode == 'blocks')),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line2))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: tBody(c, size: 15, w: FontWeight.w700, height: 20 / 15), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${kBoards[p.board]!.name} · Edited ${ago(p.updated)}',
                      style: tCaption(c, color: c.faint), overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 4),
              ProjectMenuButton(p: p),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// ⋮ on a project card: Open, Rename…, Duplicate, Download .ino (.zip with more tabs), Delete… (PR-04).
class ProjectMenuButton extends StatelessWidget {
  const ProjectMenuButton({super.key, required this.p});
  final Project p;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    return MenuButton(
      entries: () => [
        MenuEntry('Open', icon: 'open', onTap: () => s.openProject(p.id)),
        MenuEntry('Rename…', icon: 'pencil', onTap: () => showRenameProjectDialog(context, p)),
        MenuEntry('Duplicate', icon: 'copy', onTap: () => s.duplicateProject(p)),
        MenuEntry(p.files.length == 1 ? 'Download .ino' : 'Download .zip', icon: 'download', onTap: () => s.downloadProject(p)),
        MenuEntry.line,
        MenuEntry('Delete…', icon: 'trash', onTap: () => showDeleteProjectDialog(context, p)),
      ],
      builder: (context, open, toggle) => IconBtn('more', onTap: toggle, tip: 'More for ${p.name}', active: open, size: 28, iconSize: 18),
    );
  }
}

/// The little Blocks / Code preview at the top of a project card (exact Figma positions).
class Thumb extends StatelessWidget {
  const Thumb({super.key, required this.blocks});
  final bool blocks;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    Widget mb(double l, double t, double w, {bool ctl = false, bool hat = false, bool val = false}) => Positioned(
          left: l,
          top: t,
          child: Container(
            width: w,
            height: hat ? 14 : 12,
            decoration: BoxDecoration(
              color: val ? Colors.white : (ctl ? kBrand : kNavy),
              border: Border.all(color: kNavy),
              borderRadius: hat
                  ? const BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(2))
                  : BorderRadius.circular(val ? 6 : 2),
            ),
          ),
        );
    const lines = [
      [18.0, 42.0, 110.0, .28],
      [18.0, 52.0, 72.0, .55],
      [30.0, 62.0, 120.0, .44],
      [30.0, 72.0, 96.0, .44],
      [30.0, 82.0, 60.0, .44],
      [18.0, 92.0, 16.0, .55],
    ];
    return Container(
      color: c.sunk,
      child: Stack(children: [
        if (blocks) ...[
          mb(20, 40, 76, ctl: true, hat: true),
          mb(28, 56, 104),
          mb(28, 70, 64, ctl: true),
          mb(28, 84, 96),
          mb(150, 40, 72, ctl: true, hat: true),
          mb(158, 56, 92),
          mb(158, 70, 62, val: true),
        ] else
          for (final l in lines)
            Positioned(
              left: l[0],
              top: l[1],
              child: Opacity(
                opacity: l[3],
                child: Container(width: l[2], height: 5, decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(2.5))),
              ),
            ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            height: 22,
            padding: const EdgeInsets.only(left: 6, right: 8),
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              RcIcon(blocks ? 'blocks' : 'code', size: 14, color: c.ink),
              const SizedBox(width: 4),
              Text(blocks ? 'Blocks' : 'C++', style: tCaption(c, color: c.ink, w: FontWeight.w500)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// "BOARD — Connected" summary used on Home and in the editor.
class BoardSummary extends StatelessWidget {
  const BoardSummary({super.key, required this.boardId, this.extra});
  final String boardId;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final b = kBoards[boardId]!;
    Widget row(String k, String v, {bool mono = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(width: 60, child: Text(k, style: tCaption(c))),
            Expanded(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: mono ? tMono(c, size: 12, height: 18 / 12) : tBody(c, size: 13, height: 18 / 13)),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
        child: Row(children: [
          Text('BOARD', style: tH2(c)),
          const Spacer(),
          Dot(color: s.linked ? c.ok : c.disabled),
          const SizedBox(width: 6),
          Text(s.linked ? (s.onUsb ? 'Connected' : 'Preview') : 'Not connected', style: tLabel(c, w: FontWeight.w500)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(children: [
          row('Board', b.name),
          row('MCU', b.mcu),
          row('Port', s.linked ? s.portLabel : '—', mono: true),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Align(alignment: Alignment.centerLeft, child: LinkText('Board setup →', onTap: () => s.go(Screen.board))),
      ),
      if (extra != null) extra!,
    ]);
  }
}
