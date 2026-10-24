// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Recommendation {
  const Recommendation({
    required this.title,
    required this.category,
    this.coverUrl,
    this.sourceUrl,
  });

  final String title;

  /// Section header, such as "Community recommendations" or "Similar titles".
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

class RecommendationContext {
  const RecommendationContext({
    required this.title,
    required this.remoteIdByTracker,
    required this.sourceName,
    required this.mangaUrl,
    required this.client,
  });

  /// Fallback search key when no tracker ID is available.
  final String title;

  /// Lowercased tracker names mapped to remote IDs; absent trackers have no entry.
  final Map<String, String> remoteIdByTracker;

  final String sourceName;
  final String? mangaUrl;
  final http.Client client;
}

class RecommendationServiceUnavailable implements Exception {
  const RecommendationServiceUnavailable();
}

class RecommendationProviderFailure {
  const RecommendationProviderFailure(this.name, this.error);
  final String name;
  final Object error;
}

class RecommendationAllFailed implements Exception {
  const RecommendationAllFailed(this.failures);
  final List<RecommendationProviderFailure> failures;
}

class RecommendationHttpException implements Exception {
  const RecommendationHttpException(this.statusCode);
  final int statusCode;
}

abstract class RecommendationProvider {
  const RecommendationProvider();

  String get name;
  String get category;

  /// MangaUpdates shares a name across two providers, so keys must include category.
  String get key => '$name|$category';

  /// Tracker providers apply everywhere; source-specific providers override this.
  bool appliesTo(RecommendationContext ctx) => true;

  /// True only for providers reachable from browsers (CORS allows AniList).
  bool get supportsWeb => false;

  Future<List<Recommendation>> fetch(RecommendationContext ctx);
}

bool appliesOnPlatform(
  RecommendationProvider provider,
  RecommendationContext ctx, {
  bool isWeb = kIsWeb,
}) => (!isWeb || provider.supportsWeb) && provider.appliesTo(ctx);

/// Looks up the remote tracker ID when available, otherwise searches by title.
abstract class TrackerRecommendationProvider extends RecommendationProvider {
  const TrackerRecommendationProvider();

  /// Lowercased tracker name, such as `anilist` or `myanimelist`.
  String get trackerKey;

  Future<List<Recommendation>> fetchById(
    RecommendationContext ctx,
    String remoteId,
  );
  Future<List<Recommendation>> fetchBySearch(RecommendationContext ctx);

  @override
  Future<List<Recommendation>> fetch(RecommendationContext ctx) {
    final id = ctx.remoteIdByTracker[trackerKey];
    return id != null ? fetchById(ctx, id) : fetchBySearch(ctx);
  }
}
