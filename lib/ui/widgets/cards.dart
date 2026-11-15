import 'dart:convert';

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
      builder: (context, h) => EdgedBox(
        radius: 10,
        // No edge: hovering lifts the card to the raised surface instead.
        color: h ? c.raised : c.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 112, child: ProjectThumb(p: p)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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

/// The little Blocks / Code preview at the top of a project card (the design's blocksThumb / codeThumb): mini blocks
/// in the category colours, or code lines, laid out for a 268 px card and stretched with it.
class Thumb extends StatelessWidget {
  const Thumb({super.key, required this.blocks});
  final bool blocks;

  // Category colours of the blocks (web/robocore_editors.js CATS).
  static const _events = kBrand, _pins = kNavy, _light = Color(0xFF7A4FB5), _control = Color(0xFF8A5A00);
  static const _movement = Color(0xFF2F6BBF), _sensors = Color(0xFF0F7680);

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return LayoutBuilder(builder: (context, k) {
      final sx = k.maxWidth / 268;
      Widget mb(double l, double t, double w, Color color, {bool hat = false, bool round = false}) => Positioned(
            left: l,
            top: t,
            child: Container(
              width: w * sx,
              height: hat ? 14 : 12,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(color: kNavy),
                borderRadius: hat
                    ? const BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(2))
                    : BorderRadius.circular(round ? 6 : 2),
              ),
            ),
          );
      // [indent, length, opacity]
      const lines = [
        [0.0, 110.0, .5],
        [0.0, 72.0, 1.0],
        [12.0, 120.0, .8],
        [12.0, 96.0, .8],
        [12.0, 60.0, .8],
        [0.0, 16.0, 1.0],
      ];
      return Container(
        color: c.sunk,
        child: Stack(children: [
          if (blocks) ...[
            mb(20, 40, 76, _events, hat: true),
            mb(28, 56, 104, _pins),
            mb(28, 70, 96, _light),
            mb(28, 84, 64, _control),
            mb(150 * sx, 40, 72, _events, hat: true),
            mb(150 * sx + 8, 56, 92, _movement),
            mb(150 * sx + 8, 70, 62, _sensors, round: true),
          ] else
            for (final (i, l) in lines.indexed)
              Positioned(
                left: 18 + l[0],
                top: 42 + i * 10.0,
                child: Opacity(
                  opacity: l[2] * .55,
                  child: Container(width: l[1] * sx, height: 5, decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(2.5))),
                ),
              ),
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              height: 22,
              padding: const EdgeInsets.only(left: 6, right: 8),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(4)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                RcIcon(blocks ? 'blocks' : 'code', size: 14, color: c.ink),
                const SizedBox(width: 4),
                Text(blocks ? 'Blocks' : 'Code', style: tCaption(c, color: c.ink, w: FontWeight.w500)),
              ]),
            ),
          ),
        ]),
      );
    });
  }
}

/// A project card's picture: the real start of the project. Blocks: its first blocks, as the blocks editor saved
/// them (rcPreview in its Blockly JSON: [depth, text, category] rows), in their category colours. Code, or blocks
/// not yet opened in this version: the first lines of its main file.
class ProjectThumb extends StatelessWidget {
  const ProjectThumb({super.key, required this.p});
  final Project p;

  static const _colours = {
    'events': kBrand,
    'movement': Color(0xFF2F6BBF),
    'motors': Color(0xFFB84A26),
    'light': Color(0xFF7A4FB5),
    'sensors': Color(0xFF0F7680),
    'control': Color(0xFF8A5A00),
    'operators': Color(0xFF2F7A4C),
    'variables': Color(0xFFB23E7A),
    'myblocks': Color(0xFF5B6577),
    'pins': kNavy,
  };
  static final _keyword = RegExp(r'^(#include|#define|void|int|float|bool|long|const|if|else|for|while|return|unsigned|byte|char)$');

  // Old block-list categories (kBlockTypes) → the Blockly editor's category colours.
  static const _oldCats = {
    'output': 'pins',
    'control': 'control',
    'input': 'sensors',
    'math': 'operators',
    'robotics': 'movement',
    'sensors': 'sensors',
    'variables': 'variables',
    'communication': 'myblocks',
  };

  /// The first blocks as rows (depth, text, category), or null when the project isn't blocks. From the blocks
  /// editor's saved rcPreview; for a project not yet opened in it, from its block lists ("on start" / "forever").
  static List<(int, String, String)>? rows(Project p, {int max = 8}) {
    if (p.mode != 'blocks') return null;
    final json = p.blockly;
    if (json != null) {
      if (!json.contains('rcPreview')) return null;
      try {
        final list = (jsonDecode(json) as Map)['rcPreview'];
        if (list is! List || list.isEmpty) return null;
        return [
          for (final r in list)
            if (r is List && r.length >= 3) ((r[0] as num).toInt(), '${r[1]}', '${r[2]}')
        ];
      } catch (_) {
        return null;
      }
    }
    final out = <(int, String, String)>[];
    void add(String hat, List<Block> list) {
      if (out.length >= max) return;
      out.add((0, hat, 'events'));
      for (final b in list) {
        if (out.length >= max) return;
        final type = kBlockTypes[b['t']];
        if (type == null) continue;
        final words = [
          for (final part in type.parts)
            if (part is BField) '${b[part.k] ?? type.def[part.k] ?? ''}' else '$part'
        ].join(' ');
        out.add((1, words, b['t'] == 'tone' ? 'light' : _oldCats[type.cat] ?? 'myblocks'));
      }
    }

    add('on start', p.setup);
    add('forever', p.loop);
    return out;
  }

  /// The first lines of the main file that say something (no blank or comment-only lines at the top).
  static List<String> codeLines(Project p, {int max = 8}) {
    final main = p.files.where((f) => f.name.toLowerCase().endsWith('.ino')).firstOrNull ?? p.files.firstOrNull;
    final lines = (main?.content ?? '').split('\n').map((l) => l.replaceAll('\t', '  ').trimRight()).toList();
    var i = 0;
    while (i < lines.length && (lines[i].trim().isEmpty || lines[i].trim().startsWith('//'))) {
      i++;
    }
    return lines.skip(i).take(max).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final blocks = p.mode == 'blocks';
    final r = rows(p);
    final Widget body;
    if (r != null) {
      body = Container(
        decoration: BoxDecoration(color: c.sunk),
        padding: const EdgeInsets.fromLTRB(14, 38, 10, 0),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final (depth, text, cat) in r)
                Padding(
                  padding: EdgeInsets.only(left: depth * 12.0, bottom: 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _colours[cat] ?? const Color(0xFF5B6577),
                      borderRadius: depth == 0 && cat == 'events'
                          ? const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3))
                          : BorderRadius.circular(3),
                    ),
                    child: Text(text.isEmpty ? ' ' : text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: fBody,
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: cat == 'events' ? kNavy : Colors.white)),
                  ),
                ),
            ]),
          ),
        ),
      );
    } else {
      final lines = codeLines(p);
      if (lines.isEmpty) return Thumb(blocks: blocks);
      body = Container(
        color: c.sunk,
        padding: const EdgeInsets.fromLTRB(14, 38, 10, 0),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            maxWidth: double.infinity,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final l in lines)
                Text.rich(
                  TextSpan(children: [
                    for (final w in RegExp(r'(\s+|[A-Za-z_#][A-Za-z0-9_]*|.)').allMatches(l).map((m) => m.group(0)!))
                      TextSpan(text: w, style: _keyword.hasMatch(w) ? TextStyle(color: c.dark ? kBrand : const Color(0xFF8A5A00)) : null),
                  ]),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontFamily: fMono, fontSize: 9.5, height: 1.45, color: c.ink.withValues(alpha: .8)),
                ),
            ]),
          ),
        ),
      );
    }
    return Stack(children: [
      Positioned.fill(child: body),
      Positioned(
        left: 10,
        top: 10,
        child: Container(
          height: 22,
          padding: const EdgeInsets.only(left: 6, right: 8),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            RcIcon(blocks ? 'blocks' : 'code', size: 14, color: c.ink),
            const SizedBox(width: 4),
            Text(blocks ? 'Blocks' : 'Code', style: tCaption(c, color: c.ink, w: FontWeight.w500)),
          ]),
        ),
      ),
    ]);
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
    Widget row(String k, String v, {bool mono = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(width: 60, child: Text(k, style: tCaption(c))),
            Expanded(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: mono ? tMono(c, size: 12, height: 18 / 12, color: color) : tBody(c, size: 13, height: 18 / 13, color: color)),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Text('BOARD', style: tH2(c)),
          const Spacer(),
          LinkDot(on: s.linked),
          const SizedBox(width: 6),
          Text(s.linked ? (s.onUsb ? 'Connected' : 'Preview') : 'Not connected', style: tLabel(c, w: FontWeight.w500)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(children: [
          row('Board', b.name),
          row('MCU', b.mcu),
          s.linked ? row('Port', s.portLabel, mono: true) : row('Port', 'None selected', color: c.faint),
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
