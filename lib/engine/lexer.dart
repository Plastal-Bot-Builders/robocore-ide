// Tokenizer for the Arduino sketch language (a practical C++ subset).

class CompileError implements Exception {
  final int line;
  final String msg;
  CompileError(this.line, this.msg);
  @override
  String toString() => 'line $line: $msg';
}

class Tok {
  final String k; // pp, str, chr, num, id, op, eof
  final dynamic v;
  final int line;
  final bool f; // float literal
  const Tok(this.k, this.v, this.line, {this.f = false});
  String get s => v is String ? v as String : '$v';
}

String _unesc(String c) {
  switch (c) {
    case 'n':
      return '\n';
    case 't':
      return '\t';
    case 'r':
      return '\r';
    case '0':
      return '\u0000';
    default:
      return c;
  }
}

const _ops3 = ['<<=', '>>='];
const _ops2 = [
  '<=', '>=', '==', '!=', '&&', '||', '++', '--', '+=', '-=', '*=', '/=', '%=', //
  '<<', '>>', '->', '::', '|=', '&=', '^=',
];
const _single = '+-*/%<>=!&|^~?:;,(){}[].';
final _numRe = RegExp(r'^(0[xX][0-9a-fA-F]+|0[bB][01]+|\d*\.?\d+(?:[eE][-+]?\d+)?)[uUlLfF]*');
final _digit = RegExp(r'[0-9]');
final _idStart = RegExp(r'[A-Za-z_]');
final _word = RegExp(r'\w');

List<Tok> lex(String src) {
  final t = <Tok>[];
  var i = 0, line = 1;
  final n = src.length;
  String at(int j) => j < n ? src[j] : '';
  while (i < n) {
    final c = src[i];
    if (c == '\n') {
      line++;
      i++;
      continue;
    }
    if (c == ' ' || c == '\t' || c == '\r' || c == '\f' || c == '\v') {
      i++;
      continue;
    }
    if (c == '/' && at(i + 1) == '/') {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && at(i + 1) == '*') {
      final sl = line;
      i += 2;
      while (i < n && !(src[i] == '*' && at(i + 1) == '/')) {
        if (src[i] == '\n') line++;
        i++;
      }
      if (i >= n) throw CompileError(sl, 'unterminated comment');
      i += 2;
      continue;
    }
    if (c == '#') {
      var j = i;
      while (j < n && src[j] != '\n') {
        j++;
      }
      t.add(Tok('pp', src.substring(i, j), line));
      i = j;
      continue;
    }
    if (c == '"') {
      var j = i + 1;
      final sb = StringBuffer();
      while (j < n && src[j] != '"' && src[j] != '\n') {
        if (src[j] == '\\') {
          sb.write(_unesc(at(j + 1)));
          j += 2;
        } else {
          sb.write(src[j++]);
        }
      }
      if (at(j) != '"') throw CompileError(line, 'missing terminating " character');
      t.add(Tok('str', sb.toString(), line));
      i = j + 1;
      continue;
    }
    if (c == "'") {
      var j = i + 1;
      String s;
      if (at(j) == '\\') {
        s = _unesc(at(j + 1));
        j += 2;
      } else {
        s = at(j);
        j++;
      }
      if (at(j) != "'") throw CompileError(line, "missing terminating ' character");
      t.add(Tok('chr', s, line));
      i = j + 1;
      continue;
    }
    if (_digit.hasMatch(c) || (c == '.' && _digit.hasMatch(at(i + 1)))) {
      final end = i + 40 < n ? i + 40 : n;
      final m = _numRe.firstMatch(src.substring(i, end))!;
      final raw = m.group(1)!;
      num v;
      final isHex = raw.startsWith('0x') || raw.startsWith('0X');
      if (isHex) {
        v = int.parse(raw.substring(2), radix: 16);
      } else if (raw.startsWith('0b') || raw.startsWith('0B')) {
        v = int.parse(raw.substring(2), radix: 2);
      } else {
        v = num.parse(raw);
      }
      final isF = !isHex && (raw.contains('.') || raw.contains('e') || raw.contains('E'));
      t.add(Tok('num', isF ? v.toDouble() : v.toInt(), line, f: isF));
      i += m.group(0)!.length;
      continue;
    }
    if (_idStart.hasMatch(c)) {
      var j = i + 1;
      while (j < n && _word.hasMatch(src[j])) {
        j++;
      }
      t.add(Tok('id', src.substring(i, j), line));
      i = j;
      continue;
    }
    final t3 = src.substring(i, i + 3 <= n ? i + 3 : n);
    final t2 = src.substring(i, i + 2 <= n ? i + 2 : n);
    if (_ops3.contains(t3)) {
      t.add(Tok('op', t3, line));
      i += 3;
      continue;
    }
    if (_ops2.contains(t2)) {
      t.add(Tok('op', t2, line));
      i += 2;
      continue;
    }
    if (_single.contains(c)) {
      t.add(Tok('op', c, line));
      i++;
      continue;
    }
    throw CompileError(line, "stray '$c' in program");
  }
  t.add(Tok('eof', '', line));
  return t;
}
