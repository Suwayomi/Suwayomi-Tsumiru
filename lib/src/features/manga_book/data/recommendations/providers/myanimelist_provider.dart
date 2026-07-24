// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import '../recommendation_provider.dart';

// Official MyAnimeList API v2 — goes direct to MAL, avoiding Jikan's chronic
// upstream 504s (Komikku still uses Jikan and fails whenever MAL's proxy does).
// Read-only, app-level client id only — no per-user OAuth.
const _endpoint = 'https://api.myanimelist.net/v2';

// Public client id for the `X-MAL-CLIENT-ID` header — kept out of source. CI
// patches this empty default with the repo secret at build time (a single step,
// so every platform incl. fastforge/flatpak picks it up); local dev passes
// --dart-define=MAL_CLIENT_ID=... to override it. With no key the provider hides
// (see [appliesTo]) rather than erroring on every fetch.
const _clientId = String.fromEnvironment(
  'MAL_CLIENT_ID',
  defaultValue: '',
);
const _headers = {'X-MAL-CLIENT-ID': _clientId};

class MyAnimeListProvider extends TrackerRecommendationProvider {
  const MyAnimeListProvider();

  @override
  String get name => 'MyAnimeList';
  @override
  String get category => 'Community recommendations';
  @override
  String get trackerKey => 'myanimelist';

  // No client id (unconfigured build) → hide the section instead of 403-ing.
  @override
  bool appliesTo(RecommendationContext ctx) => _clientId.isNotEmpty;

  @override
  Future<List<Recommendation>> fetchById(
      RecommendationContext ctx, String remoteId) async {
    final response = await ctx.client.get(
      Uri.parse('$_endpoint/manga/$remoteId?fields=recommendations'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw RecommendationHttpException(response.statusCode);
    }
    final list =
        (jsonDecode(response.body)['recommendations'] as List?) ?? const [];
    return [
      for (final rec in list)
        if ((rec as Map)['node'] != null)
          Recommendation(
            title: (rec['node'] as Map)['title'] as String,
            category: category,
            sourceUrl:
                'https://myanimelist.net/manga/${(rec['node'] as Map)['id']}',
            coverUrl: _image((rec['node'] as Map)['main_picture'] as Map?),
          ),
    ];
  }

  @override
  Future<List<Recommendation>> fetchBySearch(RecommendationContext ctx) async {
    final response = await ctx.client.get(
      Uri.parse('$_endpoint/manga')
          .replace(queryParameters: {'q': ctx.title, 'limit': '1'}),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw RecommendationHttpException(response.statusCode);
    }
    final data = (jsonDecode(response.body)['data'] as List?) ?? const [];
    if (data.isEmpty) return const [];
    final id = ((data.first as Map)['node'] as Map?)?['id'];
    if (id == null) return const [];
    return fetchById(ctx, id.toString());
  }

  String? _image(Map? pic) {
    if (pic == null) return null;
    return (pic['medium'] as String?) ?? (pic['large'] as String?);
  }
}
