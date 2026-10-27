import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../state/app_state.dart';
import '../app_scope.dart';
import '../dialogs.dart';
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
  const PageTop({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
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
    final phone = MediaQuery.sizeOf(context).width < 760;
    final newProject = Btn('New project', icon: 'plus', kind: BtnKind.primary, onTap: () => showNewProjectDialog(context));
    if (s.projects.isEmpty) return PageBody(children: [PageTop(title: 'Projects', trailing: newProject), const _NoProjects()]);
    final list = s.filteredProjects;
    final filter = FilterBox(hint: 'Filter projects', value: s.pfilter, onChanged: (v) => s.setFilter(pfilter: v));
    return PageBody(children: [
      PageTop(
        title: 'Projects',
        subtitle: 'Saved on this device. Each computer or browser has its own projects.',
        trailing: phone
            ? Row(children: [Expanded(child: filter), const SizedBox(width: 8), newProject])
            : Row(mainAxisSize: MainAxisSize.min, children: [filter, const SizedBox(width: 12), newProject]),
      ),
      Pills(
        items: const [('all', 'All'), ('blocks', 'Blocks'), ('code', 'Code')],
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

/// Projects with nothing in it (PR-09).
class _NoProjects extends StatelessWidget {
  const _NoProjects();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.read(context);
    final c = RC.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(children: [
        Opacity(opacity: c.dark ? .5 : 1, child: Image.asset('assets/images/robot.webp', width: 300, filterQuality: FilterQuality.medium, excludeFromSemantics: true)),
        const SizedBox(height: 14),
        Text('NO PROJECTS YET', style: tH1(c), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Start with a template or an empty project.', style: tBody(c, color: c.muted), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          Btn('New project', icon: 'plus', kind: BtnKind.primary, onTap: () => showNewProjectDialog(context)),
          Btn('Browse examples', onTap: () => s.go(Screen.examples)),
        ]),
      ]),
    );
  }
}
