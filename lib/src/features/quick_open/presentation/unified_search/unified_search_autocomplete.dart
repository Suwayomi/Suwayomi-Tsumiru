// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../library/domain/library_search_query.dart';
import 'unified_search_facets.dart';

const int kUnifiedSuggestionLimit = 8;

const Set<String> _booleanKeys = {'unread', 'downloaded', 'tracked'};

const Set<String> _freeformKeys = {'rating'};

class ActiveToken {
  const ActiveToken({required this.start, required this.end, required this.raw});

  /// Half-open source range (start inclusive, end exclusive) replaced on completion.
  final int start;
  final int end;
  final String raw;

  bool get isEmpty => raw.isEmpty;

  bool get negated => raw.startsWith('-');

  String get _core => negated ? raw.substring(1) : raw;

  bool get hasColon => _core.contains(':');

  int get _colon => _core.indexOf(':');

  String? get key => hasColon ? _core.substring(0, _colon).toLowerCase() : null;

  String get partialValue => hasColon ? _core.substring(_colon + 1) : '';

  String get keyPartial => hasColon ? '' : _core;
}

class SearchSuggestion {
  const SearchSuggestion({
    required this.display,
    required this.insertText,
    required this.isKey,
  });

  /// Unquoted display text.
  final String display;

  /// Replacement text before applySuggestion adds any trailing space.
  final String insertText;

  final bool isKey;
}

typedef SuggestionEdit = ({String text, int caret});

/// Selects the space/comma-delimited token containing [caret].
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

List<SearchSuggestion> suggestFor(ActiveToken token, LibraryFacets facets) {
  if (token.isEmpty) return const [];
  final prefix = token.negated ? '-' : '';

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

/// Value completions add a space unless a separator follows; key completions stop at the colon.
SuggestionEdit applySuggestion(
  String text,
  ActiveToken token,
  SearchSuggestion suggestion,
) {
  final followed =
      token.end < text.length && (text[token.end] == ' ' || text[token.end] == ',');
  final insert = (suggestion.isKey || followed)
      ? suggestion.insertText
      : '${suggestion.insertText} ';
  final next = text.replaceRange(token.start, token.end, insert);
  return (text: next, caret: token.start + insert.length);
}

String _quote(String value) =>
    value.contains(' ') || value.contains(',') ? '"$value"' : value;
