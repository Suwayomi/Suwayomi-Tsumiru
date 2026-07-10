// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Library search DSL.
///
/// Plain words match title/author/genre/custom-tag (case-insensitive substring);
/// `key:value` tokens filter on a specific field. Multi-word values use double quotes, a
/// leading `-` negates, and terms are separated by spaces or commas. All terms
/// are AND-ed. Follows the Mihon/Komikku library-search conventions (quotes,
/// `-` exclude, AND across terms) plus explicit `tag:`/`genre:`/`rating:`
/// metatags for our per-manga user meta.
///
/// Supported keys: `tag:` (exact match on a source genre OR a custom tag,
/// case-insensitive), `genre:` (source genre, substring), `author:`, `artist:`,
/// `title:` (substring), `unread:`/`downloaded:` (bool), `rating:` (int with
/// optional `>=`/`<=`/`>`/`<`/`=`). An unrecognized key is treated as plain
/// text, so titles like `Re:Zero` still search normally.
library;

/// Flat, GraphQL-free view of the fields the DSL can match against. Keeps the
/// parser/evaluator pure and trivially unit-testable.
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
  });

  final String title;
  final String? author;
  final String? artist;
  final List<String> genres;
  final int unreadCount;
  final int downloadCount;
  final int? rating;
  final List<String> userTags;
}

enum _Field { tag, genre, author, artist, title, unread, downloaded, rating }

/// Recognized metatag keys, in display order. Exported so the search field's
/// syntax highlighter colors exactly the keys the parser understands.
const List<String> librarySearchMetatagKeys = [
  'tag',
  'genre',
  'author',
  'artist',
  'title',
  'unread',
  'downloaded',
  'rating',
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
      _ => null,
    };

class LibrarySearchQuery {
  const LibrarySearchQuery(this.terms);

  final List<SearchTerm> terms;

  bool get isEmpty => terms.isEmpty;

  bool matches(LibraryFilterFields f) => terms.every((t) => t.matches(f));

  static LibrarySearchQuery parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const LibrarySearchQuery([]);
    final terms = <SearchTerm>[];
    for (final token in _tokenize(raw)) {
      final term = _parseToken(token);
      if (term != null) terms.add(term);
    }
    return LibrarySearchQuery(terms);
  }

  /// Splits on spaces/commas, keeping double-quoted spans intact. Quote chars
  /// are consumed, so `tag:"slice of life"` becomes the single token
  /// `tag:slice of life`.
  static List<String> _tokenize(String raw) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes && (ch == ' ' || ch == ',')) {
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

    final colon = t.indexOf(':');
    if (colon > 0) {
      final field = _fieldFor(t.substring(0, colon).toLowerCase());
      if (field != null) {
        final value = t.substring(colon + 1);
        // A half-typed `tag:` shouldn't hide the whole library — skip it.
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
  }) : _field = field;

  factory SearchTerm._text(String text, bool negated) =>
      SearchTerm._(negated: negated, text: text.toLowerCase());

  factory SearchTerm._field(_Field field, String value, bool negated) =>
      SearchTerm._(negated: negated, field: field, value: value);

  final bool negated;
  final String? text;
  final _Field? _field;
  final String? value;

  bool matches(LibraryFilterFields f) {
    final res = _rawMatch(f);
    // A null result means the term imposes no constraint (an unparseable value,
    // e.g. a half-typed `-unread:t`). Negation must NOT flip it to hide-all.
    if (res == null) return true;
    return negated ? !res : res;
  }

  bool? _rawMatch(LibraryFilterFields f) {
    final t = text;
    if (t != null) {
      return f.title.toLowerCase().contains(t) ||
          (f.author?.toLowerCase().contains(t) ?? false) ||
          f.genres.any((g) => g.toLowerCase().contains(t)) ||
          f.userTags.any((tag) => tag.toLowerCase().contains(t));
    }
    final v = value!;
    switch (_field!) {
      case _Field.tag:
        // A manga's tags = source genres + custom tags. Exact match on either.
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
