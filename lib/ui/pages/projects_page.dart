import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'home_page.dart';

class FilterBox extends StatefulWidget {
  const FilterBox({super.key, required this.hint, required this.value, required this.onChanged});
  final String hint, value;
  final ValueChanged<String> onChanged;
  @override
  State<FilterBox> createState() => _FilterBoxState();
}

class _FilterBoxState extends State<FilterBox> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 760;
    return SizedBox(
      width: phone ? double.infinity : 260,
      child: RcInput(controller: _c, hint: widget.hint, icon: 'search', onChanged: widget.onChanged),
    );
  }
}

/// Page title + subtitle, with the filter box beside it (or below on phones).
class PageTop extends StatelessWidget {
  const PageTop({super.key, required this.title, required this.subtitle, this.trailing});
  final String title, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 760;
    if (phone && trailing != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: title, subtitle: subtitle),
        const SizedBox(height: 16),
        trailing!,
      ]);
    }
    return PageHeader(title: title, subtitle: subtitle, trailing: trailing);
  }
}

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final q = s.pfilter.trim().toLowerCase();
    final list = s.sortedProjects
        .where((p) =>
            (s.ptab == 'all' || p.mode == s.ptab) &&
            (q.isEmpty || p.name.toLowerCase().contains(q) || kBoards[p.board]!.name.toLowerCase().contains(q)))
        .toList();
    return PageBody(children: [
      PageTop(
        title: 'Projects',
        subtitle: 'Saved on this device until you sign in.',
        trailing: FilterBox(hint: 'Filter projects', value: s.pfilter, onChanged: (v) => s.setFilter(pfilter: v)),
      ),
      Pills(
        items: const [('all', 'All'), ('blocks', 'Blocks'), ('code', 'C++')],
        value: s.ptab,
        onChanged: (v) => s.setFilter(ptab: v),
      ),
      if (list.isEmpty)
        Text('No projects match. Try another name, or clear the filter.', style: tBody(c, color: c.muted))
      else
        CardGrid(children: [for (final p in list) ProjectCard(p: p)]),
    ]);
  }
}
