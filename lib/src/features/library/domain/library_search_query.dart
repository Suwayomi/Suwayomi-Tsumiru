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
/// optional `>=`/`<=`/`>`/`<`/`=`), `status:` (ongoing/completed/hiatus/…),
/// `source:` (source name, substring), and `tracked:` (bool, or a service name
/// like `tracked:anilist`). An unrecognized key is treated as plain text, so
/// titles like `Re:Zero` still search normally.
///
/// `{a|b}` groups alternatives: the group matches if ANY term inside it matches,
/// so `{genre:action|genre:romance}` finds either. A leading `-` negates a whole
/// group.
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
    this.status,
    this.sourceName,
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

  /// The manga's publication status, as the enum name (e.g. `COMPLETED`).
  final String? status;

  /// The source's display name.
  final String? sourceName;

  /// Lowercased names of the tracker services this manga is bound to.
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

  /// Whether [raw] contains a structured term — a recognized `key:` metatag or a
  /// `{…}` group. Quick search uses this to pick title-only vs full-DSL matching,
  /// so it agrees with [parse] on what counts (a bare `Re:Zero` does not).
  static bool hasOperator(String? raw) {
    if (raw == null) return false;
    for (final token in _tokenize(raw)) {
      if (_isStructured(token)) return true;
    }
    return false;
  }

  /// The plain-text portion of [raw] with metatag operators and `{…}` groups
  /// removed — what a *source* search should receive (`bad source:x` → `bad`,
  /// `tag:"slice of life"` → ``). Reuses the quote/brace-aware tokenizer so a
  /// quoted value isn't split into leaked fragments.
  static String plainText(String? raw) {
    if (raw == null) return '';
    return [
      for (final token in _tokenize(raw))
        if (!_isStructured(token)) token,
    ].join(' ');
  }

  /// A token is structured if it's an operator (`[-]key:…` with a recognized
  /// key) or a `{…}` group, as opposed to plain search text.
  static bool _isStructured(String token) {
    var t = token;
    if (t.length > 1 && t.startsWith('-')) t = t.substring(1);
    if (t.length > 1 && t.startsWith('{') && t.endsWith('}')) return true;
    final colon = t.indexOf(':');
    return colon > 0 && _fieldFor(t.substring(0, colon).toLowerCase()) != null;
  }

  /// Splits on spaces/commas, keeping double-quoted spans and `{…}` groups
  /// intact. Quote chars are consumed, so `tag:"slice of life"` becomes the
  /// single token `tag:slice of life`; a `{a|b}` group stays one token so its
  /// inner spaces don't split it.
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

    // `{a|b|c}` — matches if any inner alternative matches.
    if (t.length > 1 && t.startsWith('{') && t.endsWith('}')) {
      final alts = <SearchTerm>[];
      for (final part in t.substring(1, t.length - 1).split('|')) {
        final sub = _parseToken(part.trim());
        if (sub != null) alts.add(sub);
      }
      // An empty/half-typed group imposes no constraint rather than hiding all.
      if (alts.isEmpty) return null;
      return SearchTerm._group(alts, negated);
    }

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

  bool matches(LibraryFilterFields f) {
    final res = _rawMatch(f);
    // A null result means the term imposes no constraint (an unparseable value,
    // e.g. a half-typed `-unread:t`). Negation must NOT flip it to hide-all.
    if (res == null) return true;
    return negated ? !res : res;
  }

  bool? _rawMatch(LibraryFilterFields f) {
    final alts = _alternatives;
    if (alts != null) return alts.any((a) => a.matches(f));
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
      case _Field.status:
        final s = f.status;
        if (s == null) return null;
        final ns = s.toLowerCase();
        final lv = v.toLowerCase();
        // Match the exact enum name, or a partial like `hiatus` → `on_hiatus`
        // and `finished` → `publishing_finished`.
        return ns == lv || ns.replaceAll('_', ' ').contains(lv) || ns.contains(lv);
      case _Field.source:
        return f.sourceName?.toLowerCase().contains(v.toLowerCase());
      case _Field.tracked:
        final want = _parseBool(v);
        // `tracked:true`/`false` = has any tracker; otherwise match a service
        // name, e.g. `tracked:anilist`.
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
