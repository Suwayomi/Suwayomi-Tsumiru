import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _kinds = <RegExp, String>{
  RegExp(r'\bshowDialog\b(?:<[^>(]*>)?\('): 'animationStyle:',
  RegExp(r'\bshowModalBottomSheet\b(?:<[^(]*?>)?\('): 'sheetAnimationStyle:',
  RegExp(r'\bshowMenu\b(?:<[^>(]*>)?\('): 'popUpAnimationStyle:',
  RegExp(r'\bPopupMenuButton\b(?:<[^>(]*>)?\('): 'popUpAnimationStyle:',
  RegExp(r'\.showSnackBar\('): 'snackBarAnimationStyle:',
};

bool _skip(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.graphql.dart') ||
    path.contains('/l10n/generated/') ||
    path.contains('__generated__');

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
  test('every dialog, sheet, menu and snackbar call takes a motion style', () {
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
          final close = _closingParen(src, m.end);
          final args = close < 0 ? '' : _topLevel(src.substring(m.end, close));
          if (!args.contains(entry.value)) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            misses.add('${file.path}:$line missing ${entry.value}');
          }
        }
      }
    }
    expect(misses, isEmpty, reason: misses.join('\n'));
  });
}
