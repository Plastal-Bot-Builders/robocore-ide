// Code editor: syntax highlighting, line numbers, current line, find,
// auto-indent and Arduino autocomplete.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/arduino_api.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

final _kw = RegExp(
    r'^(void|int|float|long|double|bool|boolean|char|byte|word|short|const|unsigned|signed|static|volatile|if|else|for|while|do|return|break|continue|switch|case|default|true|false|String|struct|class|new|delete|sizeof|size_t|uint8_t|uint16_t|uint32_t|int8_t|int16_t|int32_t)$');
final _tokRe = RegExp(
    r'''(\/\/[^\n]*|\/\*[\s\S]*?(?:\*\/|$))|("(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])'?)|(^[ \t]*#[^\n]*)|\b(0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?[fFuUlL]*)\b|\b([A-Za-z_]\w*)\b(\s*\()?''',
    multiLine: true);
final _constRe = RegExp(r'^(HIGH|LOW|INPUT|OUTPUT|INPUT_PULLUP|LED_BUILTIN|RGB_BUILTIN|HEX|DEC|BIN|A\d)$|^[A-Z][A-Z0-9_]{2,}$');

/// Suggestions for the built-in code view (native apps): names and parameters from [kApi].
final acWords = [for (final e in kApi) (e.name, e.params)];

class CodeController extends TextEditingController {
  CodeController({super.text});
  RC colors = RC.paper;
  double fontSize = 13;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final c = colors;
    final base = TextStyle(fontFamily: fMono, fontSize: fontSize, height: 20 / 13, color: c.sPlain);
    final bold = base.copyWith(color: c.dark ? c.sKw : kNavy, fontWeight: FontWeight.w700);
    final src = text;
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _tokRe.allMatches(src)) {
      if (m.start > last) spans.add(TextSpan(text: src.substring(last, m.start)));
      last = m.end;
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(color: c.sCom)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(color: c.sStr)));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(color: c.sPre)));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(color: c.sNum)));
      } else if (m.group(5) != null) {
        final w = m.group(5)!;
        if (_kw.hasMatch(w)) {
          spans.add(TextSpan(text: w, style: bold));
        } else if (w == 'Serial' || w == 'Wire') {
          spans.add(TextSpan(text: w, style: bold));
        } else if (_constRe.hasMatch(w)) {
          spans.add(TextSpan(text: w, style: base.copyWith(color: c.sStr)));
        } else if (m.group(6) != null) {
          spans.add(TextSpan(text: w, style: base.copyWith(color: c.dark ? c.sFn : kNavy)));
        } else {
          spans.add(TextSpan(text: w));
        }
        if (m.group(6) != null) spans.add(TextSpan(text: m.group(6)));
      } else if (m.group(0)!.isNotEmpty) {
        spans.add(TextSpan(text: m.group(0)));
      }
    }
    if (last < src.length) spans.add(TextSpan(text: src.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}

class CodeView extends StatefulWidget {
  const CodeView({super.key, required this.initial, required this.fileName, required this.errorLines});
  final String initial, fileName;
  final Set<int> errorLines;

  @override
  State<CodeView> createState() => CodeViewState();
}

class CodeViewState extends State<CodeView> {
  late final CodeController _ctl = CodeController(text: widget.initial);
  final _focus = FocusNode();
  final _v = ScrollController();
  final _h = ScrollController();
  final _gutter = ScrollController();
  List<(String, String)> _ac = [];
  int _acIndex = 0;
  int _acStart = 0;
  int _line = 1;
  bool find = false;
  final _findCtl = TextEditingController();
  String _findCount = '';

  double get _fs => AppScope.read(context).settings.fontSize.toDouble();
  double get _lh => _fs * 20 / 13;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChange);
    _v.addListener(() {
      if (_gutter.hasClients && _gutter.offset != _v.offset) _gutter.jumpTo(math.min(_v.offset, _gutter.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    _v.dispose();
    _h.dispose();
    _gutter.dispose();
    _findCtl.dispose();
    super.dispose();
  }

  late String _lastText = widget.initial;
  void _onChange() {
    final s = AppScope.read(context);
    final sel = _ctl.selection;
    final off = sel.baseOffset < 0 ? 0 : math.min(sel.baseOffset, _ctl.text.length);
    final before = _ctl.text.substring(0, off);
    final lines = before.split('\n');
    final ln = lines.length;
    if (ln != _line) setState(() => _line = ln);
    s.setCursor('Ln $ln, Col ${lines.last.length + 1}');
    if (_ctl.text != _lastText) {
      _lastText = _ctl.text;
      final p = s.cur;
      final handEdit = p != null && !p.codeEdited && s.file == 0;
      s.editCode(_ctl.text);
      if (handEdit) s.showToast('Code edited by hand', body: 'The blocks will stop updating it.', info: true);
      _updateAc();
    } else if (_ac.isNotEmpty && !sel.isCollapsed) {
      setState(() => _ac = []);
    }
  }

  void _updateAc() {
    final s = AppScope.read(context);
    if (!s.settings.autocomplete) {
      if (_ac.isNotEmpty) setState(() => _ac = []);
      return;
    }
    final sel = _ctl.selection;
    if (!sel.isValid || !sel.isCollapsed) return setState(() => _ac = []);
    final before = _ctl.text.substring(0, sel.baseOffset);
    final m = RegExp(r'[A-Za-z_][\w.]*$').firstMatch(before);
    if (m == null || m.group(0)!.length < 2) return setState(() => _ac = []);
    final w = m.group(0)!.toLowerCase();
    final items = acWords.where((e) => e.$1.toLowerCase().startsWith(w) && e.$1.toLowerCase() != w).take(7).toList();
    setState(() {
      _ac = items;
      _acIndex = 0;
      _acStart = sel.baseOffset - m.group(0)!.length;
    });
  }

  void _acceptAc() {
    if (_ac.isEmpty) return;
    final (n, sig) = _ac[_acIndex];
    final end = _ctl.selection.baseOffset;
    final fn = sig.startsWith('(');
    final ins = fn ? '$n()' : n;
    final t = _ctl.text.replaceRange(_acStart, end, ins);
    final caret = _acStart + ins.length - (fn ? 1 : 0);
    setState(() => _ac = []);
    _ctl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: caret));
  }

  void _insert(String s) {
    final v = _ctl.value;
    final sel = v.selection;
    if (!sel.isValid) return;
    final t = v.text.replaceRange(sel.start, sel.end, s);
    _ctl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: sel.start + s.length));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_ac.isNotEmpty) {
      if (k == LogicalKeyboardKey.arrowDown) {
        setState(() => _acIndex = (_acIndex + 1) % _ac.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => _acIndex = (_acIndex - 1 + _ac.length) % _ac.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.tab) {
        _acceptAc();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        setState(() => _ac = []);
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.tab && !HardwareKeyboard.instance.isShiftPressed) {
      _insert('  ');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      final sel = _ctl.selection;
      if (!sel.isValid) return KeyEventResult.ignored;
      final line = _ctl.text.substring(0, sel.start).split('\n').last;
      var ind = RegExp(r'^\s*').stringMatch(line) ?? '';
      if (RegExp(r'\{\s*$').hasMatch(line)) ind += '  ';
      _insert('\n$ind');
      _scrollToCaret();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_v.hasClients) return;
      final y = 14 + (_line - 1) * _lh;
      final vp = _v.position.viewportDimension;
      if (y < _v.offset) _v.jumpTo(math.max(0, y - _lh * 2));
      if (y + _lh * 2 > _v.offset + vp) _v.jumpTo(math.min(_v.position.maxScrollExtent, y - vp + _lh * 4));
    });
  }

  /// Select a whole line and bring it into view (used by Problems).
  void gotoLine(int line) {
    final lines = _ctl.text.split('\n');
    var pos = 0;
    for (var i = 0; i < line - 1 && i < lines.length; i++) {
      pos += lines[i].length + 1;
    }
    final len = line - 1 < lines.length ? lines[line - 1].length : 0;
    _focus.requestFocus();
    _ctl.selection = TextSelection(baseOffset: pos, extentOffset: pos + len);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_v.hasClients) _v.jumpTo(math.max(0, math.min(_v.position.maxScrollExtent, (line - 4) * _lh)));
    });
  }

  void toggleFind() => setState(() {
        find = !find;
        if (!find) _findCount = '';
      });

  void _findNext(int dir) {
    final q = _findCtl.text.toLowerCase();
    if (q.isEmpty) return;
    final v = _ctl.text.toLowerCase();
    final sel = _ctl.selection;
    int i;
    if (dir > 0) {
      i = v.indexOf(q, sel.isValid ? sel.end : 0);
      if (i < 0) i = v.indexOf(q);
    } else {
      i = sel.isValid && sel.start > 0 ? v.lastIndexOf(q, sel.start - 1) : -1;
      if (i < 0) i = v.lastIndexOf(q);
    }
    if (i < 0) return;
    _ctl.selection = TextSelection(baseOffset: i, extentOffset: i + q.length);
    final ln = v.substring(0, i).split('\n').length;
    if (_v.hasClients) {
      final y = (ln - 1) * _lh;
      if (y < _v.offset || y > _v.offset + _v.position.viewportDimension - _lh * 2) {
        _v.jumpTo(math.max(0, math.min(_v.position.maxScrollExtent, y - _lh * 4)));
      }
    }
  }

  void _countFind(String q) {
    if (q.isEmpty) return setState(() => _findCount = '');
    final n = _ctl.text.toLowerCase().split(q.toLowerCase()).length - 1;
    setState(() => _findCount = n > 0 ? '$n match${n > 1 ? 'es' : ''}' : 'No matches');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = RC.of(context);
    _ctl.colors = c;
    _ctl.fontSize = _fs;

    final wrap = s.settings.wrap;
    final lineCount = '\n'.allMatches(_ctl.text).length + 1;
    final charW = _measureChar(_fs);
    final longest = _ctl.text.split('\n').fold<int>(0, (a, l) => math.max(a, l.length));
    final strut = StrutStyle(fontFamily: fMono, fontSize: _fs, height: 20 / 13, forceStrutHeight: true);

    // A pending "go to line" from the Problems tab.
    final goto = s.gotoLine;
    if (goto != null) {
      s.gotoLine = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => gotoLine(goto));
    }

    final gutter = SizedBox(
      width: 52,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _gutter,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 14, 12, 400),
          itemCount: lineCount,
          itemExtent: _lh,
          itemBuilder: (context, i) {
            final n = i + 1;
            final err = widget.errorLines.contains(n);
            return Text('$n',
                textAlign: TextAlign.right,
                style: tMono(c,
                    size: _fs,
                    height: 20 / 13,
                    color: err ? c.err : (n == _line ? c.ink : c.sLn),
                    w: err ? FontWeight.w700 : FontWeight.w400));
          },
        ),
      ),
    );

    Widget editor(double minWidth) {
      final w = wrap ? minWidth : math.max(minWidth, longest * charW + 48);
      final field = SizedBox(
        width: w,
        child: Stack(children: [
          if (!wrap)
            Positioned(
              left: 0,
              right: 0,
              top: 14 + (_line - 1) * _lh,
              height: _lh,
              child: ColoredBox(color: c.curLine),
            ),
          Focus(
            onKeyEvent: _onKey,
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textCapitalization: TextCapitalization.none,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              strutStyle: strut,
              cursorColor: c.ink,
              cursorWidth: 1.5,
              style: tMono(c, size: _fs, height: 20 / 13, color: c.sPlain),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(8, 14, 16, 120),
              ),
            ),
          ),
          if (_ac.isNotEmpty) _acBox(c, charW),
        ]),
      );
      if (wrap) return field;
      return SingleChildScrollView(controller: _h, scrollDirection: Axis.horizontal, child: field);
    }

    return Column(children: [
      if (find) _findBar(c),
      Expanded(
        child: Container(
          color: c.surface,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            gutter,
            Expanded(
              child: LayoutBuilder(
                builder: (context, k) => Scrollbar(
                  controller: _v,
                  child: SingleChildScrollView(
                    controller: _v,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: k.maxHeight),
                      child: editor(k.maxWidth),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _acBox(RC c, double charW) {
    final before = _ctl.text.substring(0, _acStart);
    final lines = before.split('\n');
    final col = lines.last.length;
    final ln = lines.length;
    return Positioned(
      left: math.max(4, 8 + col * charW),
      top: 14 + ln * _lh + 2,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: c.raised, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(8), boxShadow: popShadow),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < _ac.length; i++)
              GestureDetector(
                onTap: () {
                  _acIndex = i;
                  _acceptAc();
                  _focus.requestFocus();
                },
                child: Container(
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: i == _acIndex ? c.brandSoft : Colors.transparent, borderRadius: BorderRadius.circular(4)),
                  child: Row(children: [
                    Expanded(child: Text(_ac[i].$1, style: tMono(c, size: 12, height: 1.2), overflow: TextOverflow.ellipsis)),
                    Text(_ac[i].$2, style: tMono(c, size: 11, color: c.faint, height: 1.2)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _findBar(RC c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line2))),
      child: Row(children: [
        Expanded(
          child: RcInput(
            controller: _findCtl,
            autofocus: true,
            hint: 'Find in ${widget.fileName}',
            onChanged: _countFind,
            onSubmitted: (_) => _findNext(1),
          ),
        ),
        const SizedBox(width: 8),
        Text(_findCount, style: tCaption(c)),
        const SizedBox(width: 8),
        Btn('Previous', kind: BtnKind.plain, small: true, onTap: () => _findNext(-1)),
        const SizedBox(width: 4),
        Btn('Next', small: true, onTap: () => _findNext(1)),
        const SizedBox(width: 4),
        IconBtn('x', onTap: toggleFind, tip: 'Close find', iconSize: 16),
      ]),
    );
  }

  static final Map<double, double> _charWCache = {};
  double _measureChar(double fs) {
    return _charWCache.putIfAbsent(fs, () {
      final tp = TextPainter(
        text: TextSpan(text: 'MMMMMMMMMM', style: TextStyle(fontFamily: fMono, fontSize: fs)),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width / 10;
    });
  }
}
