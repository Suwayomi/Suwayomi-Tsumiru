// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:http/http.dart' as http;

/// One recommended title. Mirrors the fields Komikku's SManga recommendations
/// carry (title + cover + the provider's own url).
class Recommendation {
  const Recommendation({
    required this.title,
    required this.category,
    this.coverUrl,
    this.sourceUrl,
  });

  final String title;

  /// Provider grouping shown as a section header, e.g. "Community
  /// recommendations" or "Similar titles" (Komikku's per-source category).
  final String category;
  final String? coverUrl;
  final String? sourceUrl;

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'coverUrl': coverUrl,
        'sourceUrl': sourceUrl,
      };

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        title: json['title'] as String,
        category: json['category'] as String,
        coverUrl: json['coverUrl'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
      );
}

/// Everything a provider needs to decide between an exact tracker-id lookup and
/// a title search, mirroring Komikku's TrackerRecommendationPagingSource.
class RecommendationContext {
  const RecommendationContext({
    required this.title,
    required this.remoteIdByTracker,
    required this.sourceName,
    required this.mangaUrl,
    required this.client,
  });

  /// The manga's title (Komikku uses `ogTitle`), the search fallback key.
  final String title;

  /// Lowercased tracker name -> the manga's remote id on that tracker, from its
  /// track records. Empty when the series isn't tracked there.
  final Map<String, String> remoteIdByTracker;

  final String sourceName;
  final String? mangaUrl;
  final http.Client client;
}

/// A provider's HTTP call returned a non-200. Surfaced per-section as an error
/// (Komikku parity) instead of an empty list — a flaky upstream isn't "no recs".
class RecommendationHttpException implements Exception {
  const RecommendationHttpException(this.statusCode);
  final int statusCode;
}

abstract class RecommendationProvider {
  const RecommendationProvider();

  String get name;
  String get category;

  /// Unique lookup id. [name] alone collides — MangaUpdates ships two providers
  /// (community + similar) under the same name — so the per-provider Riverpod
  /// family must key on name+category, or one silently shadows the other.
  String get key => '$name|$category';

  /// Source-specific providers (Comick, MangaDex) override this; tracker
  /// providers apply everywhere.
  bool appliesTo(RecommendationContext ctx) => true;

  Future<List<Recommendation>> fetch(RecommendationContext ctx);
}

/// Base for providers backed by a tracker: query by the manga's remote id when
/// it's tracked there, otherwise search by title (Komikku's id-or-search rule).
abstract class TrackerRecommendationProvider extends RecommendationProvider {
  const TrackerRecommendationProvider();

  /// Lowercased tracker name this provider matches against (`anilist`,
  /// `myanimelist`, `mangaupdates`).
  String get trackerKey;

  Future<List<Recommendation>> fetchById(
      RecommendationContext ctx, String remoteId);
  Future<List<Recommendation>> fetchBySearch(RecommendationContext ctx);

  @override
  Future<List<Recommendation>> fetch(RecommendationContext ctx) {
    final id = ctx.remoteIdByTracker[trackerKey];
    return id != null ? fetchById(ctx, id) : fetchBySearch(ctx);
  }
}
