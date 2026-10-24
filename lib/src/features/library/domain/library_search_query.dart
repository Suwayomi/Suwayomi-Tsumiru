// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Plain words match title/author/genre/custom-tag by case-insensitive substring.
/// `key:value` restricts a field; double quotes preserve multi-word values.
/// Terms are AND-ed, separated by spaces or commas; leading `-` negates.
/// `tag:` matches genres or custom tags exactly; `genre:`, `author:`, `artist:`,
/// `title:`, and `source:` use substrings. `unread:`/`downloaded:` take bools,
/// `rating:` takes an int with optional >=/<=/>/</=, and `status:` takes a status.
/// `tracked:` takes a bool or service name. Unknown keys remain plain text (Re:Zero).
/// `{a|b}` matches any alternative; `-{a|b}` negates the whole group.
library;

import 'package:diacritic/diacritic.dart';

class LibraryFilterFields {
  const LibraryFilterFields({
    required this.title,
    this.author,
    this.artist,
    this.genres = const [],
    this.unreadCount = 0,
    this.downloadCount = 0,
    this.rating,
    this.userTags = const [],
    this.status,
    this.sourceName,
    this.sourceId,
    this.description,
    this.trackers = const {},
  });

  final String title;
  final String? author;
  final String? artist;
  final List<String> genres;
  final int unreadCount;
  final int downloadCount;
  final int? rating;
  final List<String> userTags;

  /// Publication status as an enum name, e.g. COMPLETED.
  final String? status;

  final String? sourceName;
  final String? sourceId;
  final String? description;

  /// Lowercased names of bound tracker services.
  final Set<String> trackers;
}

enum _Field {
  tag,
  genre,
  author,
  artist,
  title,
  unread,
  downloaded,
  rating,
  status,
  source,
  tracked,
}

/// Shared with syntax highlighting so it recognizes exactly the parser's keys.
const List<String> librarySearchMetatagKeys = [
  'tag',
  'genre',
  'author',
  'artist',
  'title',
  'unread',
  'downloaded',
  'rating',
  'status',
  'source',
  'tracked',
];

_Field? _fieldFor(String key) => switch (key) {
      'tag' => _Field.tag,
      'genre' => _Field.genre,
      'author' => _Field.author,
      'artist' => _Field.artist,
      'title' => _Field.title,
      'unread' => _Field.unread,
      'downloaded' => _Field.downloaded,
      'rating' => _Field.rating,
      'status' => _Field.status,
      'source' => _Field.source,
      'tracked' => _Field.tracked,
      _ => null,
    };

class LibrarySearchQuery {
  const LibrarySearchQuery(this.terms);

  final List<SearchTerm> terms;

  bool get isEmpty => terms.isEmpty;

  bool matches(LibraryFilterFields f, {bool fuzzy = false}) =>
      terms.every((t) => t.matches(f, fuzzy: fuzzy));

  static LibrarySearchQuery parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const LibrarySearchQuery([]);
    final terms = <SearchTerm>[];
    for (final token in _tokenize(raw)) {
      final term = _parseToken(token);
      if (term != null) terms.add(term);
    }
    return LibrarySearchQuery(terms);
  }

  /// Recognizes supported metatags and alternative groups; bare Re:Zero remains plain text.
  static bool hasOperator(String? raw) {
    if (raw == null) return false;
    for (final token in _tokenize(raw)) {
      if (_isStructured(token)) return true;
    }
    return false;
  }

  /// Removes structured terms for source searches, preserving quoted spans as single tokens.
  static String plainText(String? raw) {
    if (raw == null) return '';
    return [
      for (final token in _tokenize(raw))
        if (!_isStructured(token)) token,
    ].join(' ');
  }

  static bool _isStructured(String token) {
    var t = token;
    if (t.length > 1 && t.startsWith('-')) t = t.substring(1);
    if (t.length > 1 && t.startsWith('{') && t.endsWith('}')) return true;
    final colon = t.indexOf(':');
    return colon > 0 && _fieldFor(t.substring(0, colon).toLowerCase()) != null;
  }

  /// Keeps quoted spans and brace groups intact; consumes quote characters.
  static List<String> _tokenize(String raw) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    var braceDepth = 0;
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes) {
        if (ch == '{') braceDepth++;
        if (ch == '}' && braceDepth > 0) braceDepth--;
      }
      if (!inQuotes && braceDepth == 0 && (ch == ' ' || ch == ',')) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
        continue;
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }

  static SearchTerm? _parseToken(String token) {
    var negated = false;
    var t = token;
    if (t.length > 1 && t.startsWith('-')) {
      negated = true;
      t = t.substring(1);
    }
    if (t.isEmpty) return null;

    if (t.length > 1 && t.startsWith('{') && t.endsWith('}')) {
      final alts = <SearchTerm>[];
      for (final part in t.substring(1, t.length - 1).split('|')) {
        final sub = _parseToken(part.trim());
        if (sub != null) alts.add(sub);
      }
      // Ignore incomplete groups while typing rather than hiding all results.
      if (alts.isEmpty) return null;
      return SearchTerm._group(alts, negated);
    }

    final colon = t.indexOf(':');
    if (colon > 0) {
      final field = _fieldFor(t.substring(0, colon).toLowerCase());
      if (field != null) {
        final value = t.substring(colon + 1);
        // An incomplete metatag imposes no constraint while typing.
        if (value.isEmpty) return null;
        return SearchTerm._field(field, value, negated);
      }
    }
    return SearchTerm._text(t, negated);
  }
}

class SearchTerm {
  const SearchTerm._({
    required this.negated,
    this.text,
    _Field? field,
    this.value,
    List<SearchTerm>? alternatives,
  })  : _field = field,
        _alternatives = alternatives;

  factory SearchTerm._text(String text, bool negated) =>
      SearchTerm._(negated: negated, text: text.toLowerCase());

  factory SearchTerm._field(_Field field, String value, bool negated) =>
      SearchTerm._(negated: negated, field: field, value: value);

  factory SearchTerm._group(List<SearchTerm> alternatives, bool negated) =>
      SearchTerm._(negated: negated, alternatives: alternatives);

  final bool negated;
  final String? text;
  final _Field? _field;
  final String? value;
  final List<SearchTerm>? _alternatives;

  bool matches(LibraryFilterFields f, {bool fuzzy = false}) {
    final res = _rawMatch(f, fuzzy: fuzzy);
    // Invalid values impose no constraint; negation must not turn them into hide-all.
    if (res == null) return true;
    return negated ? !res : res;
  }

  bool? _rawMatch(LibraryFilterFields f, {bool fuzzy = false}) {
    final alts = _alternatives;
    if (alts != null) return alts.any((a) => a.matches(f, fuzzy: fuzzy));
    final t = text;
    if (t != null) {
      if (fuzzy) {
        return [
          f.title,
          if (f.author != null) f.author!,
          if (f.artist != null) f.artist!,
          if (f.sourceName != null) f.sourceName!,
          if (f.sourceId != null) f.sourceId!,
          if (f.description != null) f.description!,
          ...f.genres,
          ...f.userTags,
        ].any((value) => fuzzyLibraryWordMatches(t, value));
      }
      return f.title.toLowerCase().contains(t) ||
          (f.author?.toLowerCase().contains(t) ?? false) ||
          f.genres.any((g) => g.toLowerCase().contains(t)) ||
          f.userTags.any((tag) => tag.toLowerCase().contains(t));
    }
    final v = value!;
    switch (_field!) {
      case _Field.tag:
        // tag: matches either source genres or custom tags exactly.
        final lv = v.toLowerCase();
        return f.userTags.any((tag) => tag.toLowerCase() == lv) ||
            f.genres.any((g) => g.toLowerCase() == lv);
      case _Field.genre:
        final lv = v.toLowerCase();
        return f.genres.any((g) => g.toLowerCase().contains(lv));
      case _Field.author:
        return f.author?.toLowerCase().contains(v.toLowerCase()) ?? false;
      case _Field.artist:
        return f.artist?.toLowerCase().contains(v.toLowerCase()) ?? false;
      case _Field.title:
        return f.title.toLowerCase().contains(v.toLowerCase());
      case _Field.unread:
        final want = _parseBool(v);
        return want == null ? null : (f.unreadCount > 0) == want;
      case _Field.downloaded:
        final want = _parseBool(v);
        return want == null ? null : (f.downloadCount > 0) == want;
      case _Field.rating:
        return _matchRating(f.rating ?? 0, v);
      case _Field.status:
        final s = f.status;
        if (s == null) return null;
        final ns = s.toLowerCase();
        final lv = v.toLowerCase();
        return ns == lv || ns.replaceAll('_', ' ').contains(lv) || ns.contains(lv);
      case _Field.source:
        return f.sourceName?.toLowerCase().contains(v.toLowerCase());
      case _Field.tracked:
        final want = _parseBool(v);
        if (want != null) return f.trackers.isNotEmpty == want;
        final lv = v.toLowerCase();
        return f.trackers.any((name) => name.contains(lv));
    }
  }

  static bool? _parseBool(String v) => switch (v.toLowerCase()) {
        'true' || 'yes' || '1' => true,
        'false' || 'no' || '0' => false,
        _ => null,
      };

  static final _ratingSpec = RegExp(r'^(>=|<=|>|<|=)?\s*(\d+)$');

  static bool? _matchRating(int actual, String spec) {
    final m = _ratingSpec.firstMatch(spec.trim());
    if (m == null) return null; // unparseable → no constraint
    final n = int.tryParse(m.group(2)!);
    if (n == null) return null; // overflow (very long digit run) → no constraint
    return switch (m.group(1) ?? '=') {
      '>=' => actual >= n,
      '<=' => actual <= n,
      '>' => actual > n,
      '<' => actual < n,
      _ => actual == n,
    };
  }
}

bool fuzzyLibraryWordMatches(String query, String text) {
  final needle = removeDiacritics(query.toLowerCase());
  final haystack = removeDiacritics(text.toLowerCase());
  if (haystack.contains(needle)) return true;
  if (needle.isEmpty) return true;
  var previous = List<int>.filled(haystack.length + 1, 0);
  for (var i = 1; i <= needle.length; i++) {
    final row = List<int>.filled(haystack.length + 1, i);
    for (var j = 1; j <= haystack.length; j++) {
      final substitution =
          previous[j - 1] + (needle[i - 1] == haystack[j - 1] ? 0 : 1);
      final insertion = row[j - 1] + 1;
      final deletion = previous[j] + 1;
      row[j] = [
        substitution,
        insertion,
        deletion,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = row;
  }
  return previous.any((distance) => distance / needle.length <= 0.35);
}
