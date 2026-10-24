import 'package:flutter/material.dart';

TextEditingValue applyInlineMarker(TextEditingValue value, String marker) {
  final selection = value.selection;
  final text = value.text;
  final anchor = selection.isValid ? selection.start : text.length;
  final focus = selection.isValid ? selection.end : text.length;
  if (anchor == focus) {
    final next = text.replaceRange(anchor, anchor, '$marker$marker');
    final cursor = anchor + marker.length;
    return value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
  final wrapped = text.replaceRange(
    anchor,
    focus,
    '$marker${text.substring(anchor, focus)}$marker',
  );
  return value.copyWith(
    text: wrapped,
    selection: TextSelection(
      baseOffset: anchor + marker.length,
      extentOffset: focus + marker.length,
    ),
  );
}

final _numberedPrefix = RegExp(r'^\d+\. ');

TextEditingValue toggleBulletedList(TextEditingValue value) =>
    _toggleLinePrefix(
      value,
      hasPrefix: (line) => line.startsWith('- '),
      removePrefix: (line) => line.substring(2),
      addPrefix: (line, _) => '- $line',
    );

TextEditingValue toggleNumberedList(TextEditingValue value) =>
    _toggleLinePrefix(
      value,
      hasPrefix: (line) => _numberedPrefix.hasMatch(line),
      removePrefix: (line) => line.replaceFirst(_numberedPrefix, ''),
      addPrefix: (line, index) =>
          '${index + 1}. ${line.replaceFirst(_numberedPrefix, '')}',
    );

typedef _HasPrefix = bool Function(String line);
typedef _RemovePrefix = String Function(String line);
typedef _AddPrefix = String Function(String line, int index);

TextEditingValue _toggleLinePrefix(
  TextEditingValue value, {
  required _HasPrefix hasPrefix,
  required _RemovePrefix removePrefix,
  required _AddPrefix addPrefix,
}) {
  final text = value.text;
  final selection = value.selection;
  final anchor = selection.isValid ? selection.start : 0;
  final focus = selection.isValid ? selection.end : 0;

  final lines = text.split('\n');
  final starts = <int>[];
  var offset = 0;
  for (final line in lines) {
    starts.add(offset);
    offset += line.length + 1;
  }

  int lineOf(int position) {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (position >= starts[i]) return i;
    }
    return 0;
  }

  final firstLine = lineOf(anchor);
  // A selection ending exactly on a line start belongs to the previous line.
  final lastLine = lineOf(
    focus > starts[firstLine] && _isLineStart(starts, focus)
        ? focus - 1
        : focus,
  );
  final target = [for (var i = firstLine; i <= lastLine; i++) i];

  final nonBlank = target.where((i) => lines[i].trim().isNotEmpty).toList();
  if (nonBlank.isEmpty) return value;
  final removing = nonBlank.every((i) => hasPrefix(lines[i]));

  final updated = lines.toList();
  var selectedIndex = 0;
  for (final i in target) {
    if (lines[i].trim().isEmpty) continue;
    updated[i] = removing
        ? removePrefix(updated[i])
        : addPrefix(updated[i], selectedIndex);
    selectedIndex++;
  }

  return value.copyWith(
    text: updated.join('\n'),
    selection: TextSelection(
      baseOffset: starts[firstLine],
      extentOffset: starts[lastLine] + updated[lastLine].length,
    ),
  );
}

bool _isLineStart(List<int> starts, int position) => starts.contains(position);
