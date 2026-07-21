// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Title similarity + query sanitizing for the migration matcher — pure Dart,
/// unit-testable. Ports Komikku's `NormalizedLevenshtein` semantics and
/// `QuerySanitizer` so bulk matching stays at parity.
library;

import 'dart:math' as math;

/// Normalized Levenshtein similarity in [0, 1] — 1.0 for identical strings,
/// 0.0 for a total mismatch. Matches `com.aallam.similarity.NormalizedLevenshtein`:
/// `1 - editDistance / max(len(a), len(b))`, with two empty strings scoring 1.0.
double normalizedLevenshteinSimilarity(String a, String b) {
  if (a == b) return 1.0;
  final maxLen = math.max(a.length, b.length);
  if (maxLen == 0) return 1.0;
  return 1.0 - _levenshtein(a, b) / maxLen;
}

int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Two-row DP — O(min) memory.
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = math.min(
        math.min(curr[j] + 1, prev[j + 1] + 1),
        prev[j] + cost,
      );
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Code points of the whitespace + separator characters trimmed from a query's
/// ends, matching Komikku's `QuerySanitizer.CHARACTER_TRIM_CHARS`. Defined by
/// code point to keep this source ASCII-only.
const Set<int> _trimCodeUnits = {
  0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0xA0, // whitespace
  0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
  0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
  0x3000,
  0x2D, 0x5F, 0x2C, 0x3A, // - _ , :
};

/// Fancy → ASCII replacements (right/left quotes, en/em dash, ellipsis).
const Map<int, String> _specialCharReplacements = {
  0x2019: "'", // right single quote
  0x2018: "'", // left single quote
  0x201C: '"', // left double quote
  0x201D: '"', // right double quote
  0x2013: '-', // en dash
  0x2014: '-', // em dash
  0x2026: '...', // ellipsis
};

/// Sanitizes a search query the way Komikku does before hitting a source: trim
/// whitespace, drop [removePrefix], trim separator chars from the ends, and
/// normalize fancy quotes/dashes/ellipsis to plain ASCII.
String sanitizeQuery(String input, {String removePrefix = ''}) {
  var s = input.trim();
  if (removePrefix.isNotEmpty && s.startsWith(removePrefix)) {
    s = s.substring(removePrefix.length);
  }
  final units = s.codeUnits;
  var start = 0;
  var end = units.length;
  while (start < end && _trimCodeUnits.contains(units[start])) {
    start++;
  }
  while (end > start && _trimCodeUnits.contains(units[end - 1])) {
    end--;
  }
  final buffer = StringBuffer();
  for (var i = start; i < end; i++) {
    final replacement = _specialCharReplacements[units[i]];
    buffer.write(replacement ?? String.fromCharCode(units[i]));
  }
  return buffer.toString();
}
