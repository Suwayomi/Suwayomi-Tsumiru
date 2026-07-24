// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import '../recommendation_provider.dart';

// 1:1 with exh/recs/sources/MangaUpdatesPagingSource.kt.
const _endpoint = 'https://api.mangaupdates.com/v1';

abstract class _MangaUpdatesProvider extends TrackerRecommendationProvider {
  const _MangaUpdatesProvider();

  @override
  String get name => 'MangaUpdates';
  @override
  String get trackerKey => 'mangaupdates';

  /// "recommendations" (community) vs "category_recommendations" (similar).
  String get recommendationsKey;

  @override
  Future<List<Recommendation>> fetchById(
      RecommendationContext ctx, String remoteId) async {
    final response =
        await ctx.client.get(Uri.parse('$_endpoint/series/$remoteId'));
    if (response.statusCode != 200) {
      throw RecommendationHttpException(response.statusCode);
    }
    final list = (jsonDecode(response.body)[recommendationsKey] as List?) ??
        const [];
    return [
      for (final rec in list)
        Recommendation(
          title: (rec as Map)['series_name'] as String,
          category: category,
          sourceUrl: rec['series_url'] as String?,
          coverUrl: (((rec['series_image'] as Map?)?['url']) as Map?)?['original']
              as String?,
        ),
    ];
  }

  @override
  Future<List<Recommendation>> fetchBySearch(RecommendationContext ctx) async {
    final response = await ctx.client.post(
      Uri.parse('$_endpoint/series/search'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'search': ctx.title, 'stype': 'title'}),
    );
    if (response.statusCode != 200) {
      throw RecommendationHttpException(response.statusCode);
    }
    final results = (jsonDecode(response.body)['results'] as List?) ?? const [];
    if (results.isEmpty) return const [];
    final seriesId =
        ((results.first as Map)['record'] as Map?)?['series_id'];
    if (seriesId == null) return const [];
    return fetchById(ctx, seriesId.toString());
  }
}

class MangaUpdatesCommunityProvider extends _MangaUpdatesProvider {
  const MangaUpdatesCommunityProvider();
  @override
  String get category => 'Community recommendations';
  @override
  String get recommendationsKey => 'recommendations';
}

class MangaUpdatesSimilarProvider extends _MangaUpdatesProvider {
  const MangaUpdatesSimilarProvider();
  @override
  String get category => 'Similar titles';
  @override
  String get recommendationsKey => 'category_recommendations';
}
