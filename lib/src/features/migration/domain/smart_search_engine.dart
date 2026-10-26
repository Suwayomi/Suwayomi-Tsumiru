// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

library;

import 'bulk_migration_types.dart';
import 'concurrency.dart';
import 'string_similarity.dart';

typedef SearchCandidate = ({int id, String title, String? thumbnailUrl});

typedef SourceSearch = Future<List<SearchCandidate>> Function(
    String sourceId, String query);

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

  /// Actual normalized Levenshtein similarity, even for a single candidate.
  final double confidence;

  final bool singleCandidate;

  bool get hasMatch => mangaId != null;
}

class SmartSearchEngine {
  const SmartSearchEngine({
    this.eligibleThreshold = 0.4,
    this.extraSearchParams,
  });

  /// Eligibility floor, separate from the auto-migrate threshold.
  final double eligibleThreshold;
  final String? extraSearchParams;

  /// Returns the best eligible match excluding [excludeId]; a lone candidate still gets its real score.
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

/// Searches sources sequentially in priority order with rate limiting; first eligible match wins.
BulkMatcher buildSmartMatcher({
  required SourceSearch search,
  required List<String> targetSourceIds,
  required RateLimiter rateLimiter,
  Map<String, String> sourceNames = const {},
  SmartSearchEngine engine = const SmartSearchEngine(),
}) {
  return (entry, token) async {
    for (final sourceId in targetSourceIds) {
      // The saved preference may still hold the entry's own source; never search it.
      if (entry.fromSourceId != null && sourceId == entry.fromSourceId) {
        continue;
      }
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
          toSourceName: sourceNames[sourceId],
          toSourceId: sourceId,
          confidence: result.confidence,
        );
      }
    }
    return const MatchOutcome();
  };
}
