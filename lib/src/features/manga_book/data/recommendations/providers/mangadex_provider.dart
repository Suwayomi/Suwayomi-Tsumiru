// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import '../recommendation_provider.dart';

// Ports exh/md/similar/MangaDexSimilarPagingSource + SimilarHandler: pull
// similar ids from similarmanga.com, then resolve them through the MangaDex API.
const _similarApi = 'https://api.similarmanga.com/similar/';
const _mangadexApi = 'https://api.mangadex.org';
const _coverCdn = 'https://uploads.mangadex.org';

class MangaDexProvider extends RecommendationProvider {
  const MangaDexProvider();

  @override
  String get name => 'MangaDex';
  @override
  String get category => 'Similar titles';

  @override
  bool appliesTo(RecommendationContext ctx) =>
      ctx.mangaUrl != null && ctx.sourceName.toLowerCase().contains('mangadex');

  @override
  Future<List<Recommendation>> fetch(RecommendationContext ctx) async {
    // MdUtil.getMangaId: the uuid is the last path segment of the manga url.
    final uuid = ctx.mangaUrl!.replaceAll(RegExp(r'/+$'), '').split('/').last;
    final similar =
        await ctx.client.get(Uri.parse('$_similarApi$uuid.json'));
    if (similar.statusCode != 200) {
      throw RecommendationHttpException(similar.statusCode);
    }
    final ids = [
      for (final m in (jsonDecode(similar.body)['matches'] as List?) ?? const [])
        (m as Map)['id'] as String?,
    ].whereType<String>().toList();
    if (ids.isEmpty) return const [];

    final uri = Uri.parse('$_mangadexApi/manga').replace(queryParameters: {
      'ids[]': ids,
      'includes[]': 'cover_art',
      'limit': '${ids.length}',
    });
    final response = await ctx.client.get(uri);
    if (response.statusCode != 200) {
      throw RecommendationHttpException(response.statusCode);
    }
    final data = (jsonDecode(response.body)['data'] as List?) ?? const [];
    return [
      for (final m in data)
        Recommendation(
          title: _title((m as Map)['attributes'] as Map?),
          category: category,
          sourceUrl: '/manga/${m['id']}',
          coverUrl: _cover(m['id'] as String?, m['relationships'] as List?),
        ),
    ];
  }

  String _title(Map? attributes) {
    final titles = (attributes?['title'] as Map?) ?? const {};
    return (titles['en'] ?? (titles.values.isNotEmpty ? titles.values.first : null))
            as String? ??
        'Unknown';
  }

  String? _cover(String? mangaId, List? relationships) {
    if (mangaId == null || relationships == null) return null;
    for (final rel in relationships) {
      if ((rel as Map)['type'] == 'cover_art') {
        final file = (rel['attributes'] as Map?)?['fileName'] as String?;
        if (file != null) return '$_coverCdn/covers/$mangaId/$file.256.jpg';
      }
    }
    return null;
  }
}
