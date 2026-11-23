import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'home_page.dart';
import 'projects_page.dart';

class LibrariesPage extends StatelessWidget {
  const LibrariesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final q = s.libq.trim().toLowerCase();
    final list = kLibs.where((l) => q.isEmpty || '${l.name} ${l.desc} ${l.h}'.toLowerCase().contains(q)).toList();
    final phone = MediaQuery.sizeOf(context).width < 760;
    return PageBody(children: [
      PageTop(
        title: 'Libraries',
        subtitle: 'Code your sketches can #include. RoboCore libraries come with the board package.',
        trailing: FilterBox(hint: 'Search libraries', value: s.libq, onChanged: (v) => s.setFilter(libq: v)),
      ),
      RcCard(
        child: list.isEmpty
            ? Padding(padding: const EdgeInsets.all(18), child: Text('No libraries match that search.', style: tBody(c, color: c.muted)))
            : Column(children: [
                for (var i = 0; i < list.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line2))),
                    child: Tooltip(
                      message: '#include <${list[i].h}>${list[i].arch == 'esp32' ? ' · ESP32 boards only' : ''}',
                      waitDuration: const Duration(milliseconds: 800),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(list[i].name, style: tLabel(c)),
                            const SizedBox(height: 2),
                            Text(list[i].desc, style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
                          ]),
                        ),
                        const SizedBox(width: 16),
                        if (!phone) SizedBox(width: 80, child: Text(list[i].ver, style: tMono(c, size: 12, color: c.faint, height: 18 / 12))),
                        SizedBox(width: phone ? 92 : 110, child: Align(alignment: Alignment.centerRight, child: _action(context, list[i].id))),
                      ]),
                    ),
                  ),
              ]),
      ),
    ]);
  }

  Widget _action(BuildContext context, String id) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final l = kLibs.firstWhere((x) => x.id == id);
    // The design's Library Action: Install → Installing… → ✓ Installed, which turns into Remove on hover.
    if (l.kind == 'included') return const Badge2('Included', bg: kBrand, fg: kNavy);
    final inst = s.installing[id];
    if (inst != null) return Btn(inst, kind: BtnKind.plain, busy: true, small: true);
    if (s.libs[id] ?? false) {
      return Hover(
        onTap: () => s.uninstall(id),
        tooltip: 'Remove ${l.name}',
        builder: (context, h) => SizedBox(
          height: 28,
          child: h
              ? Btn('Remove', icon: 'trash', small: true, onTap: () => s.uninstall(id))
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: c.sunk, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    RcIcon('check', size: 16, color: c.ink),
                    const SizedBox(width: 6),
                    Text('Installed', style: tLabel(c)),
                  ]),
                ),
        ),
      );
    }
    return Btn('Install', icon: 'download', small: true, onTap: () => s.install(id));
  }
}
