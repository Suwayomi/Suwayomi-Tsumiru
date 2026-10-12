import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _kinds = <RegExp, RegExp>{
  RegExp(r'\bshowDialog\b'): RegExp(r'\banimationStyle:'),
  RegExp(r'\bshowModalBottomSheet\b'): RegExp(r'\bsheetAnimationStyle:'),
  RegExp(r'\bshowMenu\b'): RegExp(r'\bpopUpAnimationStyle:'),
  RegExp(r'\bPopupMenuButton\b'): RegExp(r'\bpopUpAnimationStyle:'),
  RegExp(r'\.showSnackBar\b'): RegExp(
    r'\bsnackBarAnimationStyle:\s*(?:context\.)?snackBarMotionStyle\b',
  ),
};

bool _skip(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.graphql.dart') ||
    path.contains('/l10n/generated/') ||
    path.contains('__generated__');

/// Index just past the `(` that opens a call, after an optional balanced
/// `<...>` type argument list (which may nest). -1 when the name is not called.
int _callOpen(String s, int from) {
  var i = _skipSpace(s, from);
  if (i < s.length && s[i] == '<') {
    var depth = 0;
    for (; i < s.length; i++) {
      if (s[i] == '<') depth++;
      if (s[i] == '>' && --depth == 0) {
        i++;
        break;
      }
    }
    i = _skipSpace(s, i);
  }
  return i < s.length && s[i] == '(' ? i + 1 : -1;
}

int _skipSpace(String s, int i) {
  var j = i;
  while (j < s.length && ' \n\t'.contains(s[j])) {
    j++;
  }
  return j;
}

int _closingParen(String s, int from) {
  var depth = 1;
  var i = from;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"') {
      i++;
      while (i < s.length && s[i] != c) {
        i += s[i] == r'\' ? 2 : 1;
      }
    } else if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      i = s.indexOf('\n', i);
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

String _topLevel(String args) {
  final out = StringBuffer();
  var depth = 0;
  for (final c in args.split('')) {
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    out.write(depth == 0 ? c : ' ');
  }
  return out.toString();
}

void main() {
  test(
    'every dialog, sheet, menu and snackbar call takes its motion style',
    () {
      final misses = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !_skip(f.path));
      for (final file in files) {
        final src = file.readAsStringSync();
        for (final entry in _kinds.entries) {
          for (final m in entry.key.allMatches(src)) {
            final lineStart = src.lastIndexOf('\n', m.start) + 1;
            if (src.substring(lineStart, m.start).trimLeft().startsWith('//')) {
              continue;
            }
            final open = _callOpen(src, m.end);
            if (open < 0) continue;
            final close = _closingParen(src, open);
            final args = close < 0 ? '' : _topLevel(src.substring(open, close));
            if (!entry.value.hasMatch(args)) {
              final line =
                  '\n'.allMatches(src.substring(0, m.start)).length + 1;
              misses.add('${file.path}:$line missing ${entry.value.pattern}');
            }
          }
        }
      }
      expect(misses, isEmpty, reason: misses.join('\n'));
    },
  );
}
