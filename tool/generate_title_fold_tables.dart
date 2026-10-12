// Usage: dart run tool/generate_title_fold_tables.dart
//
// Rewrites the generated tables in lib/src/features/library/domain/title_fold.dart
// from unorm_dart's NFKC. Everything above `const _single` is kept as written.
// Dev-only: unorm_dart is a dev dependency and is not shipped in the app.

import 'dart:io';

import 'package:unorm_dart/unorm_dart.dart';

const _path = 'lib/src/features/library/domain/title_fold.dart';
const _marker = 'const _single = ';

final _letter = RegExp(r'^\p{L}$', unicode: true);

const _baseRanges = [
  (0x0000, 0x024F), // Latin
  (0x1E00, 0x1EFF), // Latin Extended Additional
  (0x0370, 0x03FF), // Greek
  (0x1F00, 0x1FFF), // Greek Extended
  (0x0400, 0x04FF), // Cyrillic
  (0x3040, 0x30FF), // Hiragana and Katakana
];

final _marks = <int>[for (var m = 0x0300; m <= 0x036F; m++) m, 0x3099, 0x309A];

void main() {
  final file = File(_path);
  final text = file.readAsStringSync();
  final start = text.indexOf(_marker);
  if (start < 0) {
    throw StateError(
      '$_marker not found in $_path; run from the repository root',
    );
  }
  final tables = StringBuffer()
    ..write(_singleAndMulti())
    ..write(_compose());
  file.writeAsStringSync(text.substring(0, start) + tables.toString());
}

String _hex(int c) => '0x${c.toRadixString(16).toUpperCase()}';

String _escaped(String s) {
  final out = StringBuffer();
  for (final c in s.runes) {
    final plain = c >= 0x20 && c < 0x7F && c != 0x27 && c != 0x24 && c != 0x5C;
    out.write(
      plain
          ? String.fromCharCode(c)
          : '\\u{${c.toRadixString(16).toUpperCase()}}',
    );
  }
  return out.toString();
}

String _singleAndMulti() {
  final single = <int, int>{};
  final multi = <int, String>{};
  for (var c = 0; c <= 0xFFFF; c++) {
    if (c >= 0xD800 && c <= 0xDFFF) continue;
    final s = nfkc(String.fromCharCode(c));
    final runes = s.runes.toList();
    if (runes.length == 1) {
      if (runes.single != c) single[c] = runes.single;
    } else {
      multi[c] = s;
    }
  }
  final out = StringBuffer('const _single = <int, int>{\n');
  single.forEach((k, v) => out.writeln('  ${_hex(k)}: ${_hex(v)},'));
  out.write('};\n\nconst _multi = <int, String>{\n');
  for (final e in multi.entries) {
    final line = "  ${_hex(e.key)}: '${_escaped(e.value)}',";
    if (line.length <= 80) {
      out.writeln(line);
    } else {
      out.writeln('  ${_hex(e.key)}:');
      out.writeln("      '${_escaped(e.value)}',");
    }
  }
  out.write('};\n\n');
  return out.toString();
}

bool _isComposeBase(int b) {
  if (!_baseRanges.any((r) => b >= r.$1 && b <= r.$2)) return false;
  final s = String.fromCharCode(b);
  if (!_letter.hasMatch(s)) return false;
  final canonical = nfd(s);
  final compat = nfkc(s);
  return !(canonical != s && compat != s && compat.runes.length == 1);
}

String _compose() {
  final out = StringBuffer(
    '/// Keyed by `base << 16 | combining mark`.\nconst _compose = <int, int>{\n',
  );
  for (var b = 0; b <= 0xFFFF; b++) {
    if (!_isComposeBase(b)) continue;
    for (final m in _marks) {
      final s = nfkc(String.fromCharCode(b) + String.fromCharCode(m));
      if (s.runes.length != 1) continue;
      out.writeln('  ${_hex(b)} << 16 | ${_hex(m)}: ${_hex(s.runes.single)},');
    }
  }
  out.write('};\n');
  return out.toString();
}
