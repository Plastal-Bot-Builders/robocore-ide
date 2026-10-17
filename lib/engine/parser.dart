// Recursive-descent / Pratt parser producing a map-based AST.
import 'lexer.dart';

typedef Node = Map<String, dynamic>;

const castTypes = {'int', 'float', 'long', 'double', 'byte', 'bool', 'char', 'unsigned', 'boolean', 'word', 'String'};
const _notType = {'return', 'if', 'else', 'while', 'for', 'do', 'break', 'continue', 'switch', 'case', 'default', 'goto'};
const Map<String, int> _bp = {
  '=': 1, '+=': 1, '-=': 1, '*=': 1, '/=': 1, '%=': 1, '|=': 1, '&=': 1, '^=': 1, '<<=': 1, '>>=': 1, //
  '?': 2, '||': 3, '&&': 4, '|': 5, '^': 6, '&': 7, '==': 8, '!=': 8,
  '<': 9, '>': 9, '<=': 9, '>=': 9, '<<': 10, '>>': 10, '+': 11, '-': 11, '*': 12, '/': 12, '%': 12,
};

class Parser {
  final List<Tok> t;
  int p = 0;
  Parser(this.t);

  Tok peek([int o = 0]) => t[(p + o).clamp(0, t.length - 1)];
  Tok next() => t[p++];
  bool isTok(String v, [int o = 0]) {
    final x = peek(o);
    return (x.k == 'op' || x.k == 'id') && x.v == v;
  }

  String tokName(Tok x) => x.k == 'eof'
      ? 'end of input'
      : x.k == 'str'
          ? 'string constant'
          : "'${x.s}'";

  Tok expect(String v) {
    if (!isTok(v)) {
      final x = peek();
      final prev = p > 0 ? t[p - 1] : null;
      if (v == ';') {
        throw CompileError(prev != null && prev.line < x.line ? prev.line : x.line, "expected ';' before ${tokName(x)}");
      }
      throw CompileError(x.line, "expected '$v' before ${tokName(x)}");
    }
    return next();
  }

  int matchParen(int i) {
    var d = 0;
    for (var j = i; j < t.length; j++) {
      final x = t[j];
      if (x.k == 'op' && x.v == '(') {
        d++;
      } else if (x.k == 'op' && x.v == ')') {
        d--;
        if (d == 0) return j;
      } else if (x.k == 'eof') {
        return -1;
      }
    }
    return -1;
  }

  List<List<Tok>> _groups(List<Tok> toks) {
    final groups = <List<Tok>>[[]];
    for (final x in toks) {
      if (x.k == 'op' && x.v == ',') {
        groups.add([]);
      } else {
        groups.last.add(x);
      }
    }
    return groups;
  }

  List<Node> paramsFrom(List<Tok> toks, int line) {
    if (toks.isEmpty || (toks.length == 1 && toks[0].v == 'void')) return [];
    return _groups(toks).map((g) {
      final ids = g.where((x) => x.k == 'id').toList();
      if (ids.length < 2) throw CompileError(line, 'expected parameter name');
      final ptr = g.any((x) => x.k == 'op' && x.v == '*');
      return <String, dynamic>{
        'name': ids.last.s,
        'type': ids.sublist(0, ids.length - 1).map((x) => x.s).join(' ') + (ptr ? ' *' : ''),
      };
    }).toList();
  }

  bool looksLikeParams(List<Tok> toks) {
    if (toks.isEmpty) return true;
    var ok = true;
    for (final g in _groups(toks)) {
      if (g.length < 2 || g.any((x) => !(x.k == 'id' || (x.k == 'op' && (x.v == '&' || x.v == '*'))))) ok = false;
    }
    return ok;
  }

  Node program() {
    final fns = <String, Node>{};
    final globals = <Node>[];
    while (peek().k != 'eof') {
      final x = peek();
      if (x.k == 'pp') {
        next();
        continue;
      }
      if (isTok(';')) {
        next();
        continue;
      }
      if (x.k != 'id') throw CompileError(x.line, 'expected declaration before ${tokName(x)}');
      if (peek(1).k != 'id') throw CompileError(x.line, "'${x.s}' does not name a type");
      var q = 0;
      while (peek(q).k == 'id' && peek(q + 1).k == 'id') {
        q++;
      }
      final nameTok = peek(q);
      if (peek(q + 1).k == 'op' && peek(q + 1).v == '(') {
        final close = matchParen(p + q + 1);
        if (close < 0) throw CompileError(nameTok.line, "expected ')' at end of input");
        final inner = t.sublist(p + q + 2, close);
        final after = t[close + 1 < t.length ? close + 1 : t.length - 1];
        if (after.k == 'op' && after.v == '{') {
          final types = <String>[];
          for (var k = 0; k < q; k++) {
            types.add(next().s);
          }
          next();
          final params = paramsFrom(inner, nameTok.line);
          p = close + 2;
          if (fns.containsKey(nameTok.s)) {
            throw CompileError(nameTok.line, "redefinition of '${types.join(' ')} ${nameTok.s}()'");
          }
          fns[nameTok.s] = {'name': nameTok.s, 'type': types.join(' '), 'params': params, 'body': block(), 'line': nameTok.line};
          continue;
        }
        if (after.k == 'op' && after.v == ';' && looksLikeParams(inner)) {
          p = close + 2;
          continue;
        }
      }
      final d = decl();
      expect(';');
      globals.add(d);
    }
    return {'k': 'prog', 'fns': fns, 'globals': globals};
  }

  Node block() {
    final body = <Node>[];
    while (!isTok('}')) {
      if (peek().k == 'eof') throw CompileError(peek().line, "expected '}' at end of input");
      body.add(stmt());
    }
    next();
    return {'k': 'blk', 'body': body};
  }

  bool isDecl() =>
      (peek().k == 'id' && peek(1).k == 'id' && !_notType.contains(peek().v) && !_notType.contains(peek(1).v)) ||
      // char *name = ...
      (peek().k == 'id' && castTypes.contains(peek().v) && isTok('*', 1) && peek(2).k == 'id');

  Node stmt() {
    final x = peek();
    if (x.k == 'pp') {
      next();
      return {'k': 'nop'};
    }
    if (isTok('{')) {
      next();
      return block();
    }
    if (isTok(';')) {
      next();
      return {'k': 'nop'};
    }
    if (x.k == 'id') {
      switch (x.v) {
        case 'if':
          {
            next();
            expect('(');
            final c = expr();
            expect(')');
            final a = stmt();
            Node? b;
            if (isTok('else')) {
              next();
              b = stmt();
            }
            return {'k': 'if', 'c': c, 'a': a, 'b': b, 'line': x.line};
          }
        case 'while':
          {
            next();
            expect('(');
            final c = expr();
            expect(')');
            return {'k': 'while', 'c': c, 'body': stmt(), 'line': x.line};
          }
        case 'do':
          {
            next();
            final body = stmt();
            expect('while');
            expect('(');
            final c = expr();
            expect(')');
            expect(';');
            return {'k': 'do', 'c': c, 'body': body, 'line': x.line};
          }
        case 'for':
          {
            next();
            expect('(');
            Node? init;
            if (!isTok(';')) init = isDecl() ? decl() : {'k': 'ex', 'e': expr()};
            expect(';');
            Node? c;
            if (!isTok(';')) c = expr();
            expect(';');
            Node? step;
            if (!isTok(')')) step = expr();
            expect(')');
            return {'k': 'for', 'init': init, 'c': c, 'step': step, 'body': stmt(), 'line': x.line};
          }
        case 'return':
          {
            next();
            Node? e;
            if (!isTok(';')) e = expr();
            expect(';');
            return {'k': 'ret', 'e': e, 'line': x.line};
          }
        case 'break':
          next();
          expect(';');
          return {'k': 'brk'};
        case 'continue':
          next();
          expect(';');
          return {'k': 'cont'};
        case 'else':
          throw CompileError(x.line, "'else' without a previous 'if'");
      }
      if (isDecl()) {
        final d = decl();
        expect(';');
        return d;
      }
    }
    final e = expr();
    expect(';');
    return {'k': 'ex', 'e': e, 'line': x.line};
  }

  Node decl() {
    final types = <String>[];
    while (peek().k == 'id' && (peek(1).k == 'id' || (isTok('*', 1) && peek(2).k == 'id'))) {
      types.add(next().s);
      if (isTok('*')) {
        next();
        types.add('*');
      }
    }
    final type = types.join(' ');
    final items = <Node>[];
    final line = peek().line;
    while (true) {
      final nm = next();
      if (nm.k != 'id') throw CompileError(nm.line, 'expected identifier before ${tokName(nm)}');
      final it = <String, dynamic>{'name': nm.s, 'line': nm.line};
      if (isTok('[')) {
        next();
        it['arr'] = true;
        if (!isTok(']')) it['size'] = expr();
        expect(']');
      }
      if (isTok('=')) {
        next();
        if (isTok('{')) {
          next();
          final list = <Node>[];
          while (!isTok('}')) {
            list.add(expr(2));
            if (isTok(',')) {
              next();
            } else {
              break;
            }
          }
          expect('}');
          it['list'] = list;
        } else {
          it['init'] = expr(1);
        }
      } else if (isTok('(')) {
        next();
        it['args'] = args();
      }
      items.add(it);
      if (isTok(',')) {
        next();
      } else {
        break;
      }
    }
    return {'k': 'decl', 'type': type, 'items': items, 'line': line};
  }

  Node expr([int min = 0]) {
    var left = unary();
    for (;;) {
      final x = peek();
      if (x.k != 'op') break;
      final bp = _bp[x.v];
      if (bp == null || bp < min) break;
      next();
      if (x.v == '?') {
        final a = expr(0);
        expect(':');
        final b = expr(2);
        left = {'k': 'tern', 'c': left, 'a': a, 'b': b};
        continue;
      }
      if (bp == 1) {
        if (left['k'] != 'id' && left['k'] != 'idx') {
          throw CompileError(x.line, 'lvalue required as left operand of assignment');
        }
        left = {'k': 'asg', 'op': x.v, 't': left, 'v': expr(1), 'line': x.line};
        continue;
      }
      left = {'k': 'bin', 'op': x.v, 'a': left, 'b': expr(bp + 1), 'line': x.line};
    }
    return left;
  }

  Node unary() {
    final x = peek();
    if (x.k == 'op' && const ['-', '!', '~', '+'].contains(x.v)) {
      next();
      return {'k': 'un', 'op': x.v, 'a': unary()};
    }
    if (x.k == 'op' && (x.v == '++' || x.v == '--')) {
      next();
      return {'k': 'pre', 'op': x.v, 't': unary(), 'line': x.line};
    }
    if (x.k == 'op' && x.v == '(') {
      if (peek(1).k == 'id' && castTypes.contains(peek(1).v) && isTok(')', 2)) {
        next();
        final to = next().s;
        next();
        return {'k': 'cast', 'to': to, 'a': unary()};
      }
      next();
      final e = expr();
      expect(')');
      return postfix(e);
    }
    return postfix(primary());
  }

  Node postfix(Node e) {
    for (;;) {
      if (isTok('[')) {
        final x = next();
        final i = expr();
        expect(']');
        e = {'k': 'idx', 'a': e, 'i': i, 'line': x.line};
        continue;
      }
      if (isTok('++') || isTok('--')) {
        final x = next();
        e = {'k': 'post', 'op': x.v, 't': e, 'line': x.line};
        continue;
      }
      return e;
    }
  }

  Node primary() {
    final x = next();
    if (x.k == 'num') return {'k': 'num', 'v': x.v, 'f': x.f};
    if (x.k == 'str') return {'k': 'str', 'v': x.v};
    if (x.k == 'chr') {
      final s = x.s;
      return {'k': 'num', 'v': s.isEmpty ? 0 : s.codeUnitAt(0), 'f': false};
    }
    if (x.k == 'id') {
      if (castTypes.contains(x.v) && isTok('(')) {
        next();
        final a = expr();
        expect(')');
        return {'k': 'cast', 'to': x.s, 'a': a};
      }
      var name = x.s;
      // obj.member and Namespace::member (RoboCore::batteryVolts) are both kept as "a.b".
      while ((isTok('.') || isTok('::')) && peek(1).k == 'id') {
        next();
        name += '.${next().s}';
      }
      if (isTok('(')) {
        next();
        return {'k': 'call', 'name': name, 'args': args(), 'line': x.line};
      }
      return {'k': 'id', 'name': name, 'line': x.line};
    }
    throw CompileError(
        x.line, x.k == 'eof' ? 'expected expression at end of input' : 'expected primary-expression before ${tokName(x)}');
  }

  List<Node> args() {
    final a = <Node>[];
    while (!isTok(')')) {
      if (peek().k == 'eof') throw CompileError(peek().line, "expected ')' at end of input");
      a.add(expr(2));
      if (isTok(',')) {
        next();
      } else {
        break;
      }
    }
    expect(')');
    return a;
  }

  /// Parse a whole input as a single expression (for #define values).
  Node soloExpr() {
    final e = expr();
    if (peek().k != 'eof') throw CompileError(peek().line, 'bad #define value');
    return e;
  }
}

/// Visit every node (maps with a 'k' key) in the tree.
void walk(dynamic n, void Function(Node) f) {
  if (n == null) return;
  if (n is List) {
    for (final x in n) {
      walk(x, f);
    }
    return;
  }
  if (n is Map) {
    if (n.containsKey('k')) f(n as Node);
    for (final v in n.values) {
      if (v is Map || v is List) walk(v, f);
    }
  }
}
