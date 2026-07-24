// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import '../recommendation_provider.dart';

// 1:1 with exh/recs/sources/AniListPagingSource.kt.
const _endpoint = 'https://graphql.anilist.co/';

const _recFields = r'''
recommendations {
  edges {
    node {
      mediaRecommendation {
        countryOfOrigin
        title { romaji english native }
        synonyms
        coverImage { large }
        siteUrl
      }
    }
  }
}
''';

class AnilistProvider extends TrackerRecommendationProvider {
  const AnilistProvider();

  @override
  String get name => 'AniList';
  @override
  String get category => 'Community recommendations';
  @override
  String get trackerKey => 'anilist';

  @override
  Future<List<Recommendation>> fetchById(
      RecommendationContext ctx, String remoteId) {
    const query = '''
query Recommendations(\$id: Int!) {
  Page { media(id: \$id, type: MANGA) { $_recFields } }
}
''';
    return _run(ctx, query, {'id': int.tryParse(remoteId)});
  }

  @override
  Future<List<Recommendation>> fetchBySearch(RecommendationContext ctx) {
    const query = '''
query Recommendations(\$search: String!) {
  Page { media(search: \$search, type: MANGA) {
    title { romaji english native }
    synonyms
    $_recFields
  } }
}
''';
    return _run(ctx, query, {'search': ctx.title}, searchFilter: ctx.title);
  }

  Future<List<Recommendation>> _run(
    RecommendationContext ctx,
    String query,
    Map<String, dynamic> variables, {
    String? searchFilter,
  }) async {
    final response = await ctx.client.post(
      Uri.parse(_endpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'variables': variables}),
    );
    if (response.statusCode != 200) {
      throw RecommendationHttpException(response.statusCode);
    }
    var media = (jsonDecode(response.body)['data']?['Page']?['media']
        as List?) ??
        const [];
    if (searchFilter != null) {
      // Komikku keeps only search hits whose own title/synonyms contain the
      // query, dropping loose full-text matches.
      media = media.where((m) => _matches(m as Map, searchFilter)).toList();
    }
    final out = <Recommendation>[];
    for (final m in media) {
      final edges = ((m as Map)['recommendations']?['edges'] as List?) ??
          const [];
      for (final edge in edges) {
        final rec = ((edge as Map)['node']?['mediaRecommendation']) as Map?;
        if (rec == null) continue;
        final url = rec['siteUrl'] as String?;
        if (url == null) continue; // Komikku drops recs without a siteUrl.
        out.add(Recommendation(
          title: _title(rec),
          category: category,
          coverUrl: (rec['coverImage'] as Map?)?['large'] as String?,
          sourceUrl: url,
        ));
      }
    }
    return out;
  }

  bool _matches(Map media, String search) {
    final s = search.toLowerCase();
    final t = (media['title'] as Map?) ?? const {};
    for (final key in const ['romaji', 'english', 'native']) {
      if ((t[key] as String?)?.toLowerCase().contains(s) ?? false) return true;
    }
    for (final syn in (media['synonyms'] as List?) ?? const []) {
      if ((syn as String?)?.toLowerCase().contains(s) ?? false) return true;
    }
    return false;
  }

  // AniListPagingSource.getTitle: english, then romaji if Japanese, then a
  // synonym, then romaji if not Japanese, then native.
  String _title(Map rec) {
    final t = (rec['title'] as Map?) ?? const {};
    final english = t['english'] as String?;
    final romaji = t['romaji'] as String?;
    final native = t['native'] as String?;
    final synonym = ((rec['synonyms'] as List?) ?? const []).isNotEmpty
        ? (rec['synonyms'] as List).first as String?
        : null;
    final isJp = rec['countryOfOrigin'] == 'JP';
    if (english != null && english.isNotEmpty) return english;
    if (isJp && romaji != null && romaji.isNotEmpty) return romaji;
    if (synonym != null && synonym.isNotEmpty) return synonym;
    if (!isJp && romaji != null && romaji.isNotEmpty) return romaji;
    return native ?? 'NO NAME FOUND';
  }
}
