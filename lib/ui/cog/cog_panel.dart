// Cog's panel and buttons, as in the design (Cog Header, Context Chip, Chat Message, Hint Card,
// Suggestion, Quick Check, Concepts, Prompt Chip, Cog Composer, Cog Offline, Explain Lens).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/catalog.dart';
import '../../engine/compiler.dart' show Problem;
import '../../hw/compile_client.dart' show normalizeServerUrl;
import '../../state/app_state.dart';
import '../../state/cog.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

/// Cog's avatar: the RoboCore gear on a yellow disc.
class CogMark extends StatelessWidget {
  const CogMark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: kBrand, shape: BoxShape.circle, border: Border.all(color: kNavy, width: 1.25)),
        child: SvgPicture.asset('assets/images/cog_gear.svg', width: size * .6, height: size * .6, excludeFromSemantics: true),
      );
}

/// "Ask Cog" in the top bar (Ctrl/⌘ + I): a soft brandSoft pill (the Paper one: the bar is yellow in both themes),
/// navy while the panel is open.
class CogButton extends StatelessWidget {
  const CogButton({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.settings.cogOn) return const SizedBox.shrink();
    final on = s.cog.open;
    return Hover(
      onTap: s.cog.toggle,
      tooltip: on ? 'Close Cog (Ctrl+I)' : 'Ask Cog, your learning partner (Ctrl+I)',
      builder: (context, h) => Container(
        height: 32,
        padding: EdgeInsets.only(left: 4, right: compact ? 4 : 12),
        decoration: BoxDecoration(
          color: on ? kNavy : (h ? Colors.white : RC.paper.brandSoft),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const CogMark(size: 24),
          if (!compact) ...[
            const SizedBox(width: 8),
            Text('Ask Cog', style: TextStyle(fontFamily: fBody, fontSize: 13, fontWeight: FontWeight.w600, color: on ? kCream : kNavy)),
          ],
        ]),
      ),
    );
  }
}

/// "Explain with Cog": the inline action beside a problem.
class CogExplainButton extends StatelessWidget {
  const CogExplainButton({super.key, required this.problem, this.label = 'Explain', this.onBar = false});
  final Problem problem;
  final String label;

  /// On an inverted (navy) error line in Output: the box yellow chip of the design's Console Panel.
  final bool onBar;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.settings.cogOn) return const SizedBox.shrink();
    if (onBar) {
      return Hover(
        onTap: () => s.cog.explainError(problem),
        tooltip: 'Ask Cog to explain this error',
        builder: (context, h) => Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: h ? kBrandPressed : kBrand, borderRadius: BorderRadius.circular(3)),
          child: Text(label, style: const TextStyle(fontFamily: fBody, fontSize: 11.5, height: 1, fontWeight: FontWeight.w600, color: kNavy)),
        ),
      );
    }
    return Hover(
      onTap: () => s.cog.explainError(problem),
      tooltip: 'Ask Cog to explain this ${problem.isError ? 'error' : 'warning'}',
      builder: (context, h) => Container(
        height: 22,
        padding: const EdgeInsets.only(left: 3, right: 8),
        decoration: BoxDecoration(color: h ? kNavy.withValues(alpha: .85) : kNavy, borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const CogMark(size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontFamily: fBody, fontSize: 12, fontWeight: FontWeight.w600, color: kCream)),
        ]),
      ),
    );
  }
}

class CogPanel extends StatefulWidget {
  const CogPanel({super.key});
  @override
  State<CogPanel> createState() => _CogPanelState();
}

class _CogPanelState extends State<CogPanel> {
  final _ask = TextEditingController();
  final _scroll = ScrollController();
  String _seen = '';

  @override
  void dispose() {
    _ask.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(CogController cog) {
    final t = _ask.text;
    if (t.trim().isEmpty || cog.busy) return;
    _ask.clear();
    cog.ask(t);
  }

  // Follow the conversation while it grows, unless the student scrolled up to read. A card that
  // finishes loading (a fix, a question) or changes state counts as new.
  void _follow(CogController cog) {
    final last = cog.items.isEmpty ? null : cog.items.last;
    final shape = '${cog.items.length}:${last?.streaming}:${last?.fixState}:${last?.answered}';
    final seen = '$shape:${last?.text.length}';
    if (seen == _seen) return;
    final grew = !_seen.startsWith('$shape:');
    _seen = seen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      if (grew || p.maxScrollExtent - p.pixels < 120) _scroll.jumpTo(p.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final cog = s.cog;
    _follow(cog);
    final p = s.cur;

    final header = Container(
      height: 56,
      padding: const EdgeInsets.only(left: 14, right: 8),
      child: Row(children: [
        const CogMark(size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('COG', style: tH2(c)),
            Text('Your learning partner', style: tCaption(c, color: c.faint)),
          ]),
        ),
        Hover(
          onTap: () => s.go(Screen.settings),
          tooltip: 'Help style: change it in Settings → Cog',
          builder: (context, h) => Badge2(cog.styleLabel),
        ),
        const SizedBox(width: 4),
        IconBtn('plus', onTap: cog.items.isEmpty ? null : cog.newChat, tip: 'New conversation'),
        IconBtn('x', onTap: cog.close, tip: 'Close Cog (Ctrl+I)'),
      ]),
    );

    final notice = !s.settings.cogNoticeSeen;
    final body = ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      children: [
        if (notice) ...[_Notice(s: s), const SizedBox(height: 12)],
        _Chips(s: s),
        const SizedBox(height: 12),
        if (cog.items.isEmpty && !notice) _Welcome(blocks: p?.mode == 'blocks'),
        for (final it in cog.items) ...[_Item(item: it), const SizedBox(height: 12)],
        if (p != null && (p.learned.isNotEmpty || cog.items.isNotEmpty)) _Concepts(learned: p.learned, next: cog.nextConcept),
      ],
    );

    final prompts = cog.prompts;
    final footer = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (prompts.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (label, run) in prompts) _PromptChip(label: label, onTap: cog.busy ? null : run),
          ]),
          const SizedBox(height: 10),
        ],
        // The design's Cog Composer: the send (paper plane) inside the field.
        RcInput(
          controller: _ask,
          hint: 'Ask Cog about your code…',
          height: 40,
          onSubmitted: (_) => _send(cog),
          trailing: IconBtn('send', onTap: cog.busy ? null : () => _send(cog), tip: 'Send to Cog', size: 30, iconSize: 16),
        ),
        const SizedBox(height: 6),
        // Says that Cog is an AI and what it sees (Anthropic's rules for apps that young people use).
        Text(
          '${s.settings.cogRead ? 'Cog is an AI (Claude, made by Anthropic) and reads your project, output and serial monitor.' : 'Cog is an AI (Claude, made by Anthropic) and can’t see your project (Settings → Cog).'}'
          ' It can be wrong: check before you upload. Don’t type your name or other personal details.',
          style: tCaption(c, color: c.faint),
        ),
      ]),
    );

    return RcCard(
      color: c.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Expanded(child: body),
        footer,
      ]),
    );
  }
}

/// What Cog can see; a click jumps there.
class _Chips extends StatelessWidget {
  const _Chips({required this.s});
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final p = s.cur;
    final cog = s.cog;
    final chips = <Widget>[];
    if (p == null) return const SizedBox.shrink();
    if (!s.settings.cogRead) {
      chips.add(_Chip(icon: 'eye', label: 'Can’t see your project', onTap: () => s.go(Screen.settings)));
    } else {
      if (p.mode == 'blocks') {
        final n = p.blocklyCount ?? p.setup.length + p.loop.length;
        chips.add(_Chip(icon: 'blocks', label: '${p.name} · $n block${n == 1 ? '' : 's'}'));
        if (cog.block != null) chips.add(_Chip(icon: 'repeat', label: 'Selected: ${cog.block!.label}'));
      } else {
        final f = p.files[s.file.clamp(0, p.files.length - 1).toInt()];
        final line = RegExp(r'Ln (\d+)').firstMatch(s.cursorPos)?.group(1);
        chips.add(_Chip(icon: 'file', label: '${f.name}${line == null ? '' : ' · line $line'}'));
      }
      final errors = s.problems.where((e) => e.isError).length;
      if (s.problems.isNotEmpty) {
        chips.add(_Chip(
          icon: 'term',
          label: errors > 0 ? 'Output · $errors error${errors == 1 ? '' : 's'}' : 'Output · ${s.problems.length} warning${s.problems.length == 1 ? '' : 's'}',
          onTap: () => s.setPanelTab('problems'),
        ));
      }
      if (s.log.isNotEmpty) chips.add(_Chip(icon: 'msg', label: 'Serial Monitor', onTap: () => s.setPanelTab('serial')));
    }
    chips.add(_Chip(icon: 'chip', label: kBoards[p.board]?.name ?? p.board, onTap: () => s.go(Screen.board)));
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.onTap});
  final String icon, label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Hover(
      onTap: onTap,
      tooltip: onTap == null ? 'Cog can see this' : 'Cog can see this. Click to open it.',
      builder: (context, h) => Container(
        height: 24,
        padding: const EdgeInsets.only(left: 6, right: 8),
        decoration: BoxDecoration(color: h && onTap != null ? c.line2 : c.sunk, borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          RcIcon(icon, size: 14, color: c.ink),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label, overflow: TextOverflow.ellipsis, style: tCaption(c, color: c.ink, w: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Hover(
      onTap: onTap,
      builder: (context, h) => Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: onTap == null ? c.sunk : (h ? Color.lerp(c.brandSoft, kBrand, c.dark ? .18 : .3) : c.brandSoft),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: tCaption(c, color: onTap == null ? c.faint : c.ink, w: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Before the first question on this device: what Cog is, what goes where, and what not to type.
class _Notice extends StatelessWidget {
  const _Notice({required this.s});
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final host = Uri.tryParse(normalizeServerUrl(s.settings.compileServer))?.host ?? '';
    final server = host.isEmpty ? 'the RoboCore server' : 'the RoboCore server ($host)';
    final lines = [
      'Cog is an AI: Claude, made by Anthropic. It is not a person, and it can be wrong.',
      s.settings.cogRead
          ? 'Your questions, Cog’s answers and your project (its files, problems and the last lines of Output and the '
              'Serial Monitor) go to $server and on to Anthropic, a company in the United States, which writes the answer.'
          : 'Your questions and Cog’s answers go to $server and on to Anthropic, a company in the United States, which '
              'writes the answer. Your project stays on this device unless “Let Cog read this project” is turned on.',
      'The RoboCore server doesn’t keep them. Anthropic handles them under its own terms.',
      'Don’t type your name, where you live, or other personal details.',
    ];
    return RcCard(
      padding: const EdgeInsets.all(14),
      color: c.raised,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const CogMark(size: 24),
          const SizedBox(width: 10),
          Expanded(child: Text('BEFORE YOU ASK COG', style: tH2(c))),
        ]),
        const SizedBox(height: 10),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 7), child: Dot(color: c.ink, size: 5)),
              const SizedBox(width: 8),
              Expanded(child: Text(l, style: tBody(c, size: 13, height: 19 / 13))),
            ]),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Btn('OK, I understand', kind: BtnKind.primary, onTap: s.cog.noticeSeen),
        ),
      ]),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.blocks});
  final bool blocks;

  @override
  Widget build(BuildContext context) => _CogBubble(
        child: Text(
          blocks
              ? 'Hi! I’m Cog. Select a block and I can explain it, or ask me for a challenge. I give hints first, so you can find answers yourself.'
              : 'Hi! I’m Cog. Ask me about your code, or press Explain on a problem after Verify. I give hints first, so you can find answers yourself.',
          style: tBody(RC.of(context), size: 13, height: 19 / 13),
        ),
      );
}

class _CogBubble extends StatelessWidget {
  const _CogBubble({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CogMark(size: 24),
      const SizedBox(width: 10),
      Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(2), topRight: Radius.circular(10), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
          ),
          child: child,
        ),
      ),
    ]);
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item});
  final CogItem item;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final it = item;
    switch (it.kind) {
      case CogKind.you:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(left: 40),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const BoxDecoration(
              color: kNavy,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10), topRight: Radius.circular(2), bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
            ),
            child: Text(it.text, style: const TextStyle(fontFamily: fBody, fontSize: 13, height: 19 / 13, color: kCream)),
          ),
        );
      case CogKind.cog:
        return _CogBubble(child: it.text.isEmpty ? const _Dots() : CogText(it.text));
      case CogKind.hint:
      case CogKind.tryIt:
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((it.overline ?? '').toUpperCase(), style: tOverline(c, color: c.textBrand)),
            const SizedBox(height: 4),
            if (it.text.isEmpty) const _Dots() else CogText(it.text),
          ]),
        );
      case CogKind.notice:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.sunk, borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RcIcon('alert', size: 18, color: c.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.offline ? 'Cog is offline' : 'Cog couldn’t answer', style: tLabel(c)),
                const SizedBox(height: 2),
                Text(it.text, style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
              ]),
            ),
          ]),
        );
      case CogKind.fix:
        return _Suggestion(item: it);
      case CogKind.check:
        return _QuickCheck(item: it);
    }
  }
}

class _Dots extends StatelessWidget {
  const _Dots();
  @override
  Widget build(BuildContext context) => Text('Cog is thinking…', style: tCaption(RC.of(context), color: RC.of(context).faint));
}

/// Cog's words, with `code`, **bold**, lists and ```cpp blocks```.
class CogText extends StatelessWidget {
  const CogText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    final base = tBody(c, size: 13, height: 19 / 13);
    final out = <Widget>[];
    final parts = text.split('```');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i.isOdd) {
        final nl = part.indexOf('\n');
        final code = (nl >= 0 ? part.substring(nl + 1) : part).trimRight();
        if (code.isEmpty) continue;
        out.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(code, style: tMono(c, size: 12, height: 18 / 12)),
          ),
        ));
        continue;
      }
      final paragraphs = part.trim().split(RegExp(r'\n\s*\n'));
      for (final para in paragraphs) {
        if (para.trim().isEmpty) continue;
        for (final line in para.split('\n')) {
          final bullet = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+').firstMatch(line);
          final body = bullet == null ? line : line.substring(bullet.end);
          final rich = Text.rich(TextSpan(style: base, children: _inline(body, c, base)));
          out.add(bullet == null
              ? Padding(padding: const EdgeInsets.only(bottom: 2), child: rich)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 16, child: Text(RegExp(r'\d').hasMatch(bullet.group(0)!) ? bullet.group(0)!.trim() : '•', style: base)),
                    Expanded(child: rich),
                  ]),
                ));
        }
        out.add(const SizedBox(height: 6));
      }
    }
    if (out.isNotEmpty && out.last is SizedBox) out.removeLast();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }

  static List<InlineSpan> _inline(String s, RC c, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'`([^`]+)`|\*\*([^*]+)\*\*');
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: tMono(c, size: 12, height: 19 / 12).copyWith(backgroundColor: c.sunk)));
      } else {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(fontWeight: FontWeight.w600)));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return spans;
  }
}

/// Line changes between two versions of a file: (sign, line number in the new file or 0, text).
/// Only changed lines and one line of context around them; '…' marks skipped lines.
List<(String, int, String)> cogDiff(String before, String after) {
  final a = before.split('\n'), b = after.split('\n');
  final n = a.length, m = b.length;
  if (n * m > 400000) {
    return [('…', 0, 'The whole file changes.')];
  }
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final all = <(String, int, String)>[];
  var i = 0, j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[i] == b[j]) {
      all.add((' ', j + 1, b[j]));
      i++;
      j++;
    } else if (i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1])) {
      all.add(('−', 0, a[i])); // removed lines first, then the lines that replace them
      i++;
    } else {
      all.add(('+', j + 1, b[j]));
      j++;
    }
  }
  final keep = List<bool>.filled(all.length, false);
  for (var k = 0; k < all.length; k++) {
    if (all[k].$1 != ' ') {
      for (var d = -1; d <= 1; d++) {
        if (k + d >= 0 && k + d < all.length) keep[k + d] = true;
      }
    }
  }
  final out = <(String, int, String)>[];
  for (var k = 0; k < all.length; k++) {
    if (keep[k]) {
      out.add(all[k]);
    } else if (out.isNotEmpty && out.last.$1 != '…' && k > 0 && keep[k - 1]) {
      out.add(('…', 0, ''));
    }
  }
  if (out.isNotEmpty && out.last.$1 == '…') out.removeLast();
  return out;
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.item});
  final CogItem item;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final f = item.fix;
    if (item.streaming || f == null) {
      return _CogBubble(child: Text('Cog is preparing a fix…', style: tCaption(c, color: c.faint)));
    }
    final p = s.cur;
    final before = item.before ?? p?.files.where((x) => x.name == f.file).firstOrNull?.content ?? '';
    final rows = cogDiff(before, f.newContent);
    final firstLine = rows.where((r) => r.$1 == '+').firstOrNull?.$2;
    return EdgedBox(
      radius: 8,
      color: c.raised,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Expanded(child: Text('SUGGESTED FIX', style: tOverline(c))),
            Text('${f.file}${firstLine == null ? '' : ' · line $firstLine'}', style: tCaption(c, color: c.faint)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(f.explanation, style: tBody(c, size: 13, height: 18 / 13)),
        ),
        for (final (sign, _, line) in rows.take(40))
          Container(
            color: sign == '+' ? c.brandSoft : (sign == '−' ? c.sunk : Colors.transparent),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 14, child: Text(sign == ' ' ? '' : sign, style: tMono(c, size: 12, color: c.muted))),
              Expanded(
                child: Text(sign == '…' ? '…' : line,
                    style: tMono(c, size: 12, color: sign == '−' ? c.muted : c.ink, w: sign == '+' ? FontWeight.w700 : FontWeight.w400)),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: switch (item.fixState) {
            'applied' => Row(children: [
                RcIcon('check', size: 16, color: c.ok),
                const SizedBox(width: 6),
                Expanded(child: Text('Applied. Undo with Ctrl+Z in the code.', style: tCaption(c, color: c.muted))),
              ]),
            'dismissed' => Text('Not applied.', style: tCaption(c, color: c.muted)),
            _ => Row(children: [
                Btn('Apply', icon: 'check', kind: BtnKind.primary, onTap: s.cog.busy ? null : () => s.cog.applyFix(item)),
                const SizedBox(width: 8),
                Btn('Not now', kind: BtnKind.plain, onTap: () => s.cog.dismissFix(item)),
                const Spacer(),
                Text('Undo with Ctrl+Z', style: tCaption(c, color: c.faint)),
              ]),
          },
        ),
      ]),
    );
  }
}

class _QuickCheck extends StatefulWidget {
  const _QuickCheck({required this.item});
  final CogItem item;
  @override
  State<_QuickCheck> createState() => _QuickCheckState();
}

class _QuickCheckState extends State<_QuickCheck> {
  int? _pick;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    final it = widget.item;
    final q = it.check;
    if (it.streaming || q == null) {
      return _CogBubble(child: Text('Cog is writing a quick question…', style: tCaption(c, color: c.faint)));
    }
    final picked = it.answered ? it.picked : _pick;
    final right = it.answered && it.picked == q.answer;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('QUICK CHECK', style: tOverline(c, color: c.textBrand)),
        const SizedBox(height: 6),
        Text(q.question, style: tBody(c, size: 13, height: 18 / 13)),
        const SizedBox(height: 8),
        for (var i = 0; i < q.options.length; i++)
          Hover(
            onTap: it.answered ? null : () => setState(() => _pick = i),
            builder: (context, h) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                _Radio(on: picked == i),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(q.options[i],
                      style: RegExp(r'[;(){}=]').hasMatch(q.options[i]) ? tMono(c, size: 12) : tBody(c, size: 13, height: 18 / 13)),
                ),
                if (it.answered && i == q.answer) RcIcon('check', size: 16, color: c.ok),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        if (!it.answered)
          Btn('Check', kind: BtnKind.outline, onTap: _pick == null ? null : () => s.cog.answer(it, _pick!))
        else ...[
          Text(right ? 'Right!' : 'Not quite.', style: tLabel(c)),
          const SizedBox(height: 2),
          Text(q.explanation, style: tBody(c, size: 13, color: c.muted, height: 18 / 13)),
          if (right) ...[
            const SizedBox(height: 6),
            Text('Added to what you’ve learned: ${q.concept}', style: tCaption(c, color: c.textBrand, w: FontWeight.w600)),
          ] else ...[
            const SizedBox(height: 6),
            Btn('Try again', kind: BtnKind.plain, onTap: () {
              setState(() => _pick = null);
              s.cog.retry(it);
            }),
          ],
        ],
      ]),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.ink, width: 1.5)),
      child: on ? Container(width: 8, height: 8, decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle)) : null,
    );
  }
}

/// "You’ve learned" in this project, with the next concept outlined.
class _Concepts extends StatelessWidget {
  const _Concepts({required this.learned, this.next});
  final List<String> learned;
  final String? next;

  @override
  Widget build(BuildContext context) {
    final c = RC.of(context);
    Widget pill(String label, bool done) => Container(
          height: 24,
          padding: const EdgeInsets.only(left: 6, right: 8),
          decoration: BoxDecoration(
            color: done ? c.ink : c.brandSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (done) RcIcon('check', size: 12, color: c.bg) else Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.ink))),
            const SizedBox(width: 4),
            Text(done ? label : '$label · next', style: tCaption(c, color: done ? c.bg : c.ink, w: FontWeight.w600)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: c.sunk, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('YOU’VE LEARNED', style: tOverline(c, color: c.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in learned) pill(l, true),
          if (next != null) pill(next!, false),
        ]),
        if (learned.isEmpty) ...[
          const SizedBox(height: 6),
          Text('Ideas you learn with Cog in this project collect here.', style: tCaption(c, color: c.faint)),
        ],
      ]),
    );
  }
}
