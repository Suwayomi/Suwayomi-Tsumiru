// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../library/domain/library_search_query.dart';
import 'unified_search_facets.dart';

/// Max value suggestions shown for one operator, so a big library doesn't flood
/// the overlay.
const int kUnifiedSuggestionLimit = 8;

/// Operators whose only sensible values are true/false (no library facet).
const Set<String> _booleanKeys = {'unread', 'downloaded', 'tracked'};

/// Operators with free-form values we can't enumerate (suggest nothing).
const Set<String> _freeformKeys = {'rating'};

/// The word under the caret, plus a parse of it as a possible `[-]key:value`.
class ActiveToken {
  const ActiveToken({required this.start, required this.end, required this.raw});

  /// Offsets in the source text that this token occupies (replace [start, end)).
  final int start;
  final int end;
  final String raw;

  bool get isEmpty => raw.isEmpty;

  bool get negated => raw.startsWith('-');

  String get _core => negated ? raw.substring(1) : raw;

  bool get hasColon => _core.contains(':');

  int get _colon => _core.indexOf(':');

  /// The operator key when a colon is present (lowercased), else null.
  String? get key => hasColon ? _core.substring(0, _colon).toLowerCase() : null;

  /// Text typed after the colon (the value being completed).
  String get partialValue => hasColon ? _core.substring(_colon + 1) : '';

  /// Text typed when no colon yet — a candidate operator key.
  String get keyPartial => hasColon ? '' : _core;
}

/// A single autocomplete row.
class SearchSuggestion {
  const SearchSuggestion({
    required this.display,
    required this.insertText,
    required this.isKey,
  });

  /// Shown to the user (unquoted, readable).
  final String display;

  /// Replaces the active token (before any trailing space applySuggestion adds).
  final String insertText;

  /// Key completion (`source:`) vs value completion (`source:MangaDex`).
  final bool isKey;
}

/// Result of accepting a suggestion: the new field text and where to put the caret.
typedef SuggestionEdit = ({String text, int caret});

/// Isolates the token under [caret] — from the last space/comma before it to the
/// next one at/after it — so completion targets exactly what's being typed.
ActiveToken activeTokenAt(String text, int caret) {
  final c = caret.clamp(0, text.length);
  bool isBoundary(String ch) => ch == ' ' || ch == ',';

  var start = c;
  while (start > 0 && !isBoundary(text[start - 1])) {
    start--;
  }
  var end = c;
  while (end < text.length && !isBoundary(text[end])) {
    end++;
  }
  return ActiveToken(start: start, end: end, raw: text.substring(start, end));
}

/// Autocomplete rows for the current [token] against library [facets].
List<SearchSuggestion> suggestFor(ActiveToken token, LibraryFacets facets) {
  if (token.isEmpty) return const [];
  final prefix = token.negated ? '-' : '';

  // Key mode: no colon yet — offer operator keys that start with what's typed.
  if (!token.hasColon) {
    final typed = token.keyPartial.toLowerCase();
    return [
      for (final key in librarySearchMetatagKeys)
        if (key.startsWith(typed))
          SearchSuggestion(
            display: '$key:',
            insertText: '$prefix$key:',
            isKey: true,
          ),
    ];
  }

  // Value mode: a recognized key with a (possibly empty) partial value.
  final key = token.key!;
  if (_freeformKeys.contains(key)) return const [];

  final candidates = _booleanKeys.contains(key)
      ? const ['true', 'false']
      : facets.valuesFor(key);
  if (candidates == null) return const [];

  final needle = token.partialValue.toLowerCase();
  final out = <SearchSuggestion>[];
  for (final value in candidates) {
    if (!value.toLowerCase().contains(needle)) continue;
    // Already typed in full — nothing left to complete, so don't echo it back.
    if (value.toLowerCase() == needle) continue;
    out.add(SearchSuggestion(
      display: '$key:$value',
      insertText: '$prefix$key:${_quote(value)}',
      isKey: false,
    ));
    if (out.length >= kUnifiedSuggestionLimit) break;
  }
  return out;
}

/// Applies [suggestion], splicing it over the active [token] and returning the
/// new text + caret. Value completions get a trailing space so the next term can
/// follow; key completions stop after the colon so the user types the value.
SuggestionEdit applySuggestion(
  String text,
  ActiveToken token,
  SearchSuggestion suggestion,
) {
  final insert =
      suggestion.isKey ? suggestion.insertText : '${suggestion.insertText} ';
  final next = text.replaceRange(token.start, token.end, insert);
  return (text: next, caret: token.start + insert.length);
}

/// Quotes a value containing separators so the DSL tokenizer keeps it whole.
String _quote(String value) =>
    value.contains(' ') || value.contains(',') ? '"$value"' : value;
