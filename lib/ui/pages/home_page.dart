import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../dialogs.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Scrollable page body with the Figma page padding (28 / 32).
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.gap = 24});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 760;
    return SingleChildScrollView(
      padding: phone ? const EdgeInsets.fromLTRB(16, 20, 16, 24) : const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
        ],
      ),
    );
  }
}

class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.link, this.onLink});
  final String title;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(child: Text(title.toUpperCase(), style: tH2(c))),
        if (link != null) LinkText(link!, onTap: onLink),
      ]),
    );
  }
}

/// Lays out cards in columns of a fixed max width, wrapping as needed.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.cardWidth = 268, this.gap = 16, this.maxColumns});
  final List<Widget> children;
  final double cardWidth, gap;
  final int? maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, k) {
      var cols = ((k.maxWidth + gap) / (cardWidth + gap)).floor().clamp(1, 99).toInt();
      if (maxColumns != null && cols > maxColumns!) cols = maxColumns!;
      final w = cols == 1 ? k.maxWidth : cardWidth;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

const _tplIcons = {'traffic': 'clock', 'line': 'robot', 'obstacle': 'radar', 'melody': 'wave'};

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final recent = s.sortedProjects.take(3).toList();
    final first = recent.isEmpty ? null : recent.first;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 760;

    final hero = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: phone ? null : 264,
        color: kBrand,
        child: Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            child: Image.asset('assets/images/contours.png', width: 1168, height: 264, fit: BoxFit.fill),
          ),
          if (width >= 980)
            Positioned(right: 60, top: 6, child: Image.asset('assets/images/robot.webp', width: 340, filterQuality: FilterQuality.medium)),
          Padding(
            padding: phone ? const EdgeInsets.fromLTRB(22, 28, 22, 28) : const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: phone ? MainAxisSize.min : MainAxisSize.max,
              children: [
                const Text('ROBOCORE V2 · CLASSROOM ROBOT',
                    style: TextStyle(fontFamily: fDisplay, fontWeight: FontWeight.w600, fontSize: 12, height: 16 / 12, letterSpacing: .96, color: kNavy)),
                const SizedBox(height: 10),
                Text(s.needsProfile ? 'WELCOME' : 'WELCOME BACK, ${s.firstName.toUpperCase()}',
                    style: TextStyle(
                        fontFamily: fDisplay, fontWeight: FontWeight.w700, fontSize: phone ? 30 : 36, height: 40 / 36, color: kNavy)),
                const SizedBox(height: 10),
                const Text('Build. Code. Create.', style: TextStyle(fontFamily: fBody, fontSize: 14, height: 20 / 14, color: kNavy)),
                const SizedBox(height: 20),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _HeroBtn(label: 'New project', icon: 'plus', primary: true, onTap: () => showNewProjectDialog(context)),
                  if (first != null) _HeroBtn(label: 'Open ${first.name}', onTap: () => s.openProject(first.id)),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );

    final recentSec = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHead('Recent projects', link: 'All projects →', onLink: () => s.go(Screen.projects)),
      if (recent.isEmpty)
        Text('No projects yet. Start one with New project.', style: tBody(c, color: c.muted))
      else
        LayoutBuilder(builder: (context, k) {
          final cols = k.maxWidth >= 836 ? 3 : (k.maxWidth >= 540 ? 2 : 1);
          final w = cols == 1 ? k.maxWidth : ((k.maxWidth - 16 * (cols - 1)) / cols).clamp(0, 268).toDouble();
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final p in recent.take(cols == 2 ? 2 : 3)) SizedBox(width: w, child: ProjectCard(p: p)),
          ]);
        }),
    ]);

    final boardSec = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHead('Your board'),
      RcCard(child: BoardSummary(boardId: s.board)),
    ]);

    final tiles = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHead('Start from a template', link: 'All examples →', onLink: () => s.go(Screen.examples)),
      LayoutBuilder(builder: (context, k) {
        final cols = k.maxWidth >= 900 ? 4 : (k.maxWidth >= 480 ? 2 : 1);
        final w = (k.maxWidth - 16 * (cols - 1)) / cols;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (final id in const ['traffic', 'line', 'obstacle', 'melody'])
            SizedBox(width: w, child: _TemplateTile(id: id, icon: _tplIcons[id]!)),
        ]);
      }),
    ]);

    return PageBody(children: [
      hero,
      if (width >= 1100)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: recentSec),
          const SizedBox(width: 24),
          SizedBox(width: 280, child: boardSec),
        ])
      else ...[
        recentSec,
        boardSec,
      ],
      tiles,
    ]);
  }
}

class _HeroBtn extends StatelessWidget {
  const _HeroBtn({required this.label, this.icon, this.primary = false, required this.onTap});
  final String label;
  final String? icon;
  final bool primary;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Hover(
      onTap: onTap,
      builder: (context, h) => Container(
        height: 32,
        padding: const EdgeInsets.only(left: 12, right: 14),
        decoration: BoxDecoration(
          color: primary ? (h ? kNavyHover : kNavy) : (h ? Colors.white.withValues(alpha: .3) : Colors.transparent),
          border: Border.all(color: kNavy),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[RcIcon(icon!, size: 16, color: primary ? kCream : kNavy), const SizedBox(width: 8)],
          Text(label,
              style: TextStyle(
                  fontFamily: fBody, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, color: primary ? kCream : kNavy)),
        ]),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.id, required this.icon});
  final String id, icon;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    final c = RC.of(context);
    final e = exampleById(id);
    return Hover(
      onTap: () => s.openExample(id),
      builder: (context, h) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: h ? c.faint : c.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(8)),
            child: RcIcon(icon, size: 18, color: c.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: tLabel(c), overflow: TextOverflow.ellipsis),
              Text(e.tag, style: tCaption(c, color: c.faint), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}
