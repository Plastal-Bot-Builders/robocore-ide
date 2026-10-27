import 'package:flutter/material.dart' hide Thumb;

import '../../data/catalog.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../dialogs.dart';
import '../widgets/cards.dart' show Thumb;
import '../widgets/common.dart';
import 'home_page.dart';
import 'projects_page.dart';

class ExamplesPage extends StatelessWidget {
  const ExamplesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final q = s.exq.trim().toLowerCase();
    final list = kExamples
        .where((e) => (s.excat == 'All' || e.cat == s.excat) && (q.isEmpty || '${e.name} ${e.desc} ${e.cat}'.toLowerCase().contains(q)))
        .toList();
    return PageBody(children: [
      PageTop(
        title: 'Examples',
        subtitle: 'Opening an example makes a copy you can change.',
        trailing: FilterBox(hint: 'Search examples', value: s.exq, onChanged: (v) => s.setFilter(exq: v)),
      ),
      Pills(items: [for (final k in kExCats) (k, k)], value: s.excat, onChanged: (v) => s.setFilter(excat: v)),
      if (list.isEmpty)
        Text('No examples match that search.', style: tBody(c, color: c.muted))
      else
        CardGrid(children: [for (final e in list) ExampleCard(e: e)]),
    ]);
  }
}

class ExampleCard extends StatelessWidget {
  const ExampleCard({super.key, required this.e});
  final Example e;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final adv = e.level == 'Advanced';
    return Hover(
      onTap: () => showExampleDialog(context, e),
      tooltip: 'Preview ${e.name}',
      builder: (context, h) => Container(
        constraints: const BoxConstraints(minHeight: 156),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: h ? c.faint : c.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.ink)),
              child: RcIcon(kExIcon[e.id] ?? 'bolt', size: 20, color: c.ink),
            ),
            const Spacer(),
            Badge2(e.level, bg: adv ? c.ink : c.sunk, fg: adv ? c.bg : c.ink),
          ]),
          const SizedBox(height: 10),
          Text(e.name, style: tBody(c, size: 15, w: FontWeight.w700, height: 20 / 15), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(e.desc, style: tBody(c, size: 13, color: c.muted, height: 18 / 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Text('${e.hasBlocks ? 'Blocks + Code' : 'Code'} · ${e.boards}', style: tCaption(c, color: c.faint), overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

/// An example's preview before it is copied into your projects (EX-03).
Future<void> showExampleDialog(BuildContext context, Example e) => showDialog<void>(
      context: context,
      barrierColor: const Color(0x521B2A41),
      builder: (dctx) {
        final s = AppScope.read(context);
        final c = RC.of(dctx);
        final adv = e.level == 'Advanced';
        void open() {
          Navigator.of(dctx).pop();
          s.openExample(e.id);
        }

        return DialogFrame(
          title: e.name,
          subtitle: e.desc,
          onSubmit: open,
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [
              Badge2(e.level, bg: adv ? c.ink : c.sunk, fg: adv ? c.bg : c.ink),
              Badge2(e.cat, bg: c.sunk, fg: c.ink),
            ]),
            const SizedBox(height: 14),
            SizedBox(height: 120, child: EdgedBox(radius: 8, edge: c.line, child: Thumb(blocks: e.hasBlocks))),
            const SizedBox(height: 12),
            Text(e.hasBlocks ? 'Opens as a Blocks project; switch to C++ any time.' : 'Opens as a C++ project.',
                style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
          ]),
          actions: [
            Btn('Cancel', kind: BtnKind.plain, onTap: () => Navigator.of(dctx).pop()),
            Btn('Open as new project', icon: 'open', kind: BtnKind.primary, onTap: open),
          ],
        );
      },
    );
