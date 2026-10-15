import 'package:flutter/material.dart';

import '../../theme.dart';
import '../app_scope.dart';
import '../dialogs.dart' show RadioDot;
import '../widgets/common.dart';
import 'home_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final st = s.settings;

    Widget card(String title, List<Widget> rows) => RcCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title.toUpperCase(), style: tH2(c))),
            for (var i = 0; i < rows.length; i++)
              Container(
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line2))),
                child: rows[i],
              ),
          ]),
        );

    Widget row(String label, Widget trailing, {String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: tLabel(c, w: FontWeight.w500)),
                if (hint != null) ...[const SizedBox(height: 2), Text(hint, style: tCaption(c))],
              ]),
            ),
            const SizedBox(width: 16),
            trailing,
          ]),
        );

    Widget theme(String key, String name, String desc, Color sw) {
      final on = st.theme == key;
      return Hover(
        onTap: () => s.updateSettings((x) => x.theme = key),
        builder: (context, h) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: on ? c.brandSoft : (h ? c.sunk : Colors.transparent),
            border: Border.all(color: on ? c.ink : c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            RadioDot(on: on),
            const SizedBox(width: 10),
            Container(
              width: 36,
              height: 24,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: sw, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
              alignment: Alignment.topCenter,
              child: Container(height: 6, color: kBrand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: tLabel(c)),
                Text(desc, style: tCaption(c), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
    }

    final phone = MediaQuery.sizeOf(context).width < 760;
    final themes = [
      theme('paper', 'Paper', 'The box colours', kCream),
      theme('navy', 'Navy', 'Dark, for low light', kNavy),
    ];

    return PageBody(children: [
      const PageHeader(title: 'Settings', subtitle: 'Saved automatically on this device.'),
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            card('Appearance', [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: phone
                    ? Column(children: [themes[0], const SizedBox(height: 12), themes[1]])
                    : Row(children: [Expanded(child: themes[0]), const SizedBox(width: 12), Expanded(child: themes[1])]),
              ),
            ]),
            const SizedBox(height: 20),
            card('Editor', [
              row(
                  'Font size',
                  RcSelect<int>(
                    value: st.fontSize,
                    width: 110,
                    label: 'Font size',
                    items: [for (final n in const [12, 13, 14, 15, 16, 18]) (n, '$n px')],
                    onChanged: (v) => s.updateSettings((x) => x.fontSize = v),
                  )),
              row('Autocomplete', RcSwitch(value: st.autocomplete, label: 'Autocomplete', onChanged: (v) => s.updateSettings((x) => x.autocomplete = v)),
                  hint: 'Suggest Arduino functions as you type.'),
              row('Word wrap', RcSwitch(value: st.wrap, label: 'Word wrap', onChanged: (v) => s.updateSettings((x) => x.wrap = v))),
            ]),
            const SizedBox(height: 20),
            card('General', [
              row('Language',
                  RcSelect<String>(value: st.lang, width: 130, label: 'Language', items: const [('English', 'English')], onChanged: (_) {})),
              row('Auto-save projects', RcSwitch(value: st.autosave, label: 'Auto-save projects', onChanged: (v) => s.updateSettings((x) => x.autosave = v)),
                  hint: 'Every 30 seconds and before upload.'),
            ]),
          ]),
        ),
      ),
    ]);
  }
}
