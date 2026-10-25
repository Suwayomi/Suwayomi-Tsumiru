// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../recommendations/recommendation_provider.dart';

part 'cover_site_search.g.dart';

typedef CoverCandidate = ({String title, String coverUrl});

enum CoverSite {
  anilist('AniList'),
  myanimelist('MyAnimeList'),
  kitsu('Kitsu'),
  mangaupdates('MangaUpdates');

  const CoverSite(this.label);
  final String label;

  bool get supportsWeb => switch (this) {
    CoverSite.anilist || CoverSite.kitsu => true,
    CoverSite.myanimelist || CoverSite.mangaupdates => false,
  };
}

// CI patches this default; local builds can pass --dart-define=MAL_CLIENT_ID=... .
const _malClientId = String.fromEnvironment('MAL_CLIENT_ID', defaultValue: '');

bool coverSiteVisible(CoverSite site, {bool isWeb = kIsWeb}) {
  if (isWeb && !site.supportsWeb) return false;
  if (site == CoverSite.myanimelist && _malClientId.isEmpty) return false;
  return true;
}

Duration? _noCoverSiteRetry(int retryCount, Object error) => null;

/// Cover links for [query] from one cover site; each site fails independently.
@Riverpod(retry: _noCoverSiteRetry)
Future<List<CoverCandidate>> coverSiteResults(
  Ref ref,
  CoverSite site, {
  String? query,
}) async {
  final title = query?.trim() ?? '';
  if (title.isEmpty) return const [];
  // Closing the picker disposes this provider and aborts its request.
  final client = http.Client();
  ref.onDispose(client.close);
  return searchCoverSite(site, client, title);
}

Future<List<CoverCandidate>> searchCoverSite(
  CoverSite site,
  http.Client client,
  String query,
) => switch (site) {
  CoverSite.anilist => _searchAnilist(client, query),
  CoverSite.myanimelist => _searchMyAnimeList(client, query),
  CoverSite.kitsu => _searchKitsu(client, query),
  CoverSite.mangaupdates => _searchMangaUpdates(client, query),
}.timeout(const Duration(seconds: 30));

Future<List<CoverCandidate>> _searchAnilist(
  http.Client client,
  String query,
) async {
  const operation = r'''query ($search: String) {
  Page(perPage: 10, page: 1) {
    media(search: $search, type: MANGA) {
      title { english romaji }
      coverImage { extraLarge large }
    }
  }
}''';
  final response = await client.post(
    Uri.parse('https://graphql.anilist.co'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({
      'query': operation,
      'variables': {'search': query},
    }),
  );
  if (response.statusCode != 200) {
    throw RecommendationHttpException(response.statusCode);
  }
  final media =
      (jsonDecode(response.body)['data']?['Page']?['media'] as List?) ??
      const [];
  final out = <CoverCandidate>[];
  for (final entry in media) {
    final titles = ((entry as Map)['title'] as Map?) ?? const {};
    final images = (entry['coverImage'] as Map?) ?? const {};
    final cover =
        (images['extraLarge'] as String?) ?? (images['large'] as String?);
    if (cover == null || cover.isEmpty) continue;
    out.add((
      title:
          (titles['english'] as String?) ?? (titles['romaji'] as String?) ?? '',
      coverUrl: cover,
    ));
    if (out.length == 10) break;
  }
  return out;
}

Future<List<CoverCandidate>> _searchMyAnimeList(
  http.Client client,
  String query,
) async {
  final response = await client.get(
    Uri.parse('https://api.myanimelist.net/v2/manga').replace(
      queryParameters: {'q': query, 'limit': '10', 'fields': 'main_picture'},
    ),
    headers: const {'X-MAL-CLIENT-ID': _malClientId},
  );
  if (response.statusCode != 200) {
    throw RecommendationHttpException(response.statusCode);
  }
  final data = (jsonDecode(response.body)['data'] as List?) ?? const [];
  final out = <CoverCandidate>[];
  for (final entry in data) {
    final node = (entry as Map)['node'] as Map?;
    final picture = node?['main_picture'] as Map?;
    final cover =
        (picture?['large'] as String?) ?? (picture?['medium'] as String?);
    if (cover == null || cover.isEmpty) continue;
    out.add((title: (node?['title'] as String?) ?? '', coverUrl: cover));
    if (out.length == 10) break;
  }
  return out;
}

Future<List<CoverCandidate>> _searchKitsu(
  http.Client client,
  String query,
) async {
  final response = await client.get(
    Uri.parse('https://kitsu.app/api/edge/manga')
        .replace(queryParameters: {'filter[text]': query, 'page[limit]': '10'}),
  );
  if (response.statusCode != 200) {
    throw RecommendationHttpException(response.statusCode);
  }
  final data = (jsonDecode(response.body)['data'] as List?) ?? const [];
  final out = <CoverCandidate>[];
  for (final entry in data) {
    final attributes = (entry as Map)['attributes'] as Map?;
    final cover =
        ((attributes?['posterImage'] as Map?) ?? const {})['large'] as String?;
    if (cover == null || cover.isEmpty) continue;
    out.add((
      title: (attributes?['canonicalTitle'] as String?) ?? '',
      coverUrl: cover,
    ));
    if (out.length == 10) break;
  }
  return out;
}

Future<List<CoverCandidate>> _searchMangaUpdates(
  http.Client client,
  String query,
) async {
  final response = await client.post(
    Uri.parse('https://api.mangaupdates.com/v1/series/search'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'search': query, 'perpage': 10}),
  );
  if (response.statusCode != 200) {
    throw RecommendationHttpException(response.statusCode);
  }
  final results = (jsonDecode(response.body)['results'] as List?) ?? const [];
  final out = <CoverCandidate>[];
  for (final entry in results) {
    final record = (entry as Map)['record'] as Map?;
    final cover =
        ((((record?['image'] as Map?) ?? const {})['url'] as Map?) ??
                const {})['original']
            as String?;
    if (cover == null || cover.isEmpty) continue;
    out.add((title: (record?['title'] as String?) ?? '', coverUrl: cover));
    if (out.length == 10) break;
  }
  return out;
}
