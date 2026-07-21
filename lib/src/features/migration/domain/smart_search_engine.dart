// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Migration match scoring — ports Komikku's regular (single-query) smart
/// search. Pure over an injected search action, so it's unit-testable and the
/// bulk runner can drive it through its rate limiter.
library;

import 'bulk_migration_types.dart';
import 'concurrency.dart';
import 'string_similarity.dart';

/// A source-search hit reduced to what the matcher needs (id + title for
/// scoring, thumbnail for the list card).
typedef SearchCandidate = ({int id, String title, String? thumbnailUrl});

/// Searches one source for [query], returning its candidates.
typedef SourceSearch = Future<List<SearchCandidate>> Function(
    String sourceId, String query);

/// Best regular-search match for one title.
class SmartSearchResult {
  const SmartSearchResult({
    this.mangaId,
    this.title,
    this.thumbnailUrl,
    this.confidence = 0.0,
    this.singleCandidate = false,
  });

  final int? mangaId;
  final String? title;
  final String? thumbnailUrl;

  /// Real normalized-Levenshtein score of the chosen candidate (never the
  /// single-candidate 1.0 shortcut).
  final double confidence;

  /// True when the source returned exactly one candidate — provenance only, so
  /// a lone unrelated result can't masquerade as a perfect match.
  final bool singleCandidate;

  bool get hasMatch => mangaId != null;
}

class SmartSearchEngine {
  const SmartSearchEngine({
    this.eligibleThreshold = 0.4,
    this.extraSearchParams,
  });

  /// Komikku's `MIN_ELIGIBLE_THRESHOLD` — candidates below this are discarded.
  /// It is a FILTER floor, not an auto-migrate threshold.
  final double eligibleThreshold;
  final String? extraSearchParams;

  /// Single-query search against display titles. ALWAYS computes the real
  /// similarity — deliberate divergence: Komikku shortcuts a lone single-query
  /// single-candidate to 1.0, here that only sets [SmartSearchResult.singleCandidate].
  /// Returns the best eligible candidate, excluding [excludeId] (the source itself).
  Future<SmartSearchResult> regularSearch({
    required String title,
    required Future<List<SearchCandidate>> Function(String query) search,
    int? excludeId,
  }) async {
    final extra = extraSearchParams?.trim();
    final builtQuery =
        (extra != null && extra.isNotEmpty) ? '$title $extra' : title;
    final candidates = await search(sanitizeQuery(builtQuery));
    if (candidates.isEmpty) return const SmartSearchResult();

    final singleCandidate = candidates.length == 1;
    SearchCandidate? best;
    var bestScore = -1.0;
    for (final c in candidates) {
      if (excludeId != null && c.id == excludeId) continue;
      final score = normalizedLevenshteinSimilarity(title, c.title);
      if (score < eligibleThreshold) continue;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best == null) return const SmartSearchResult();
    return SmartSearchResult(
      mangaId: best.id,
      title: best.title,
      thumbnailUrl: best.thumbnailUrl,
      confidence: bestScore,
      singleCandidate: singleCandidate,
    );
  }
}

/// Builds the runner's matcher: walks [targetSourceIds] in priority order
/// (strictly sequential, no source concurrency — the biggest Cloudflare/rate
/// multiplier), rate-limited, and takes the FIRST source with an eligible match
/// (self-matches excluded). The score sets the review/auto-select tier in the runner.
BulkMatcher buildSmartMatcher({
  required SourceSearch search,
  required List<String> targetSourceIds,
  required RateLimiter rateLimiter,
  Map<String, String> sourceNames = const {},
  SmartSearchEngine engine = const SmartSearchEngine(),
}) {
  return (entry, token) async {
    for (final sourceId in targetSourceIds) {
      token.throwIfCancelled();
      final result = await engine.regularSearch(
        title: entry.fromTitle,
        excludeId: entry.fromMangaId,
        search: (query) async {
          await rateLimiter.acquire(token);
          return search(sourceId, query);
        },
      );
      if (result.hasMatch) {
        return MatchOutcome(
          toMangaId: result.mangaId,
          toTitle: result.title,
          toThumbnailUrl: result.thumbnailUrl,
          toSourceName: sourceNames[sourceId] ?? sourceId,
          confidence: result.confidence,
        );
      }
    }
    return const MatchOutcome();
  };
}
