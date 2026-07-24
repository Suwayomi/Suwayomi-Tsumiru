// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import '../recommendation_provider.dart';

// 1:1 with exh/recs/sources/ComickPagingSource.kt. Only applies to a
// Comick-sourced manga; reads recommendations off that manga's own Comick page.
const _thumbnailBase = 'https://meo.comick.pictures/';

class ComickProvider extends RecommendationProvider {
  const ComickProvider();

  @override
  String get name => 'Comick';
  @override
  String get category => 'Community recommendations';

  @override
  bool appliesTo(RecommendationContext ctx) =>
      ctx.mangaUrl != null && ctx.sourceName.toLowerCase().contains('comick');

  @override
  Future<List<Recommendation>> fetch(RecommendationContext ctx) async {
    // The Comick extension stores the manga url as '/comic/{hid}#'.
    final uri = Uri.parse('https://api.comick.fun/v1.0${ctx.mangaUrl}')
        .replace(queryParameters: {'tachiyomi': 'true'});
    final response = await ctx.client.get(uri, headers: const {
      'Referer': 'api.comick.fun/',
      'User-Agent': 'Tachiyomi',
    });
    if (response.statusCode != 200) {
      throw RecommendationHttpException(response.statusCode);
    }
    final recs = (((jsonDecode(response.body)['comic'] as Map?)
            ?['recommendations']) as List?) ??
        const [];
    return [
      for (final rec in recs)
        if ((rec as Map)['relates'] != null)
          Recommendation(
            title: (rec['relates'] as Map)['title'] as String,
            category: category,
            sourceUrl: '/comic/${(rec['relates'] as Map)['hid']}#',
            coverUrl: _cover((rec['relates'] as Map)['md_covers'] as List?),
          ),
    ];
  }

  String? _cover(List? covers) {
    if (covers == null || covers.isEmpty) return null;
    final b2key = (covers.first as Map)['b2key'] as String?;
    return b2key == null ? null : '$_thumbnailBase$b2key';
  }
}
