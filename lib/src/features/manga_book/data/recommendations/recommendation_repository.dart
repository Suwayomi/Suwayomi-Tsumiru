// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../constants/enum.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../auth/data/auth_credentials_store.dart';
import '../../../offline/data/offline_server_identity_repository.dart';
import '../../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../tracking/controller/manga_track_records_controller.dart';
import '../../../tracking/data/tracker_repository.dart';
import '../../presentation/manga_details/controller/manga_details_controller.dart';
import 'providers/anilist_provider.dart';
import 'providers/comick_provider.dart';
import 'providers/mangadex_provider.dart';
import 'providers/mangaupdates_provider.dart';
import 'providers/myanimelist_provider.dart';
import 'recommendation_provider.dart';

part 'recommendation_repository.g.dart';

// Komikku's RecommendationPagingSource.createSources order.
const _allProviders = <RecommendationProvider>[
  AnilistProvider(),
  MangaUpdatesCommunityProvider(),
  MangaUpdatesSimilarProvider(),
  MyAnimeListProvider(),
  MangaDexProvider(),
  ComickProvider(),
];

Duration? _noRecommendationRetry(int retryCount, Object error) => null;

/// The recommendation context (title, tracker remote ids, source) for [mangaId]
/// plus the providers that apply to it. Built once and shared by every section.
@Riverpod(retry: _noRecommendationRetry)
Future<({RecommendationContext ctx, List<RecommendationProvider> providers})?>
recommendationSetup(Ref ref, int mangaId) async {
  final manga = await ref.watch(mangaWithIdProvider(mangaId: mangaId).future);
  final title = manga?.title;
  if (manga == null || title == null || title.isEmpty) return null;

  final trackers = await ref.watch(trackersProvider.future);
  final records = await ref.watch(
    mangaTrackRecordsProvider(mangaId: mangaId).future,
  );
  final nameById = {for (final t in trackers) t.id: t.name.toLowerCase()};
  final remoteIdByTracker = <String, String>{};
  for (final rec in records) {
    final name = nameById[rec.trackerId];
    if (name != null) remoteIdByTracker[name] = rec.remoteId;
  }

  final client = http.Client();
  ref.onDispose(client.close);
  final ctx = RecommendationContext(
    title: title,
    remoteIdByTracker: remoteIdByTracker,
    sourceName: manga.source?.name ?? '',
    mangaUrl: manga.url,
    client: client,
  );
  return (
    ctx: ctx,
    providers: _allProviders.where((p) => p.appliesTo(ctx)).toList(),
  );
}

/// Every applicable provider's recommendations for [mangaId], flattened and
/// deduped, for the inline Suggestions row on the manga details page. Suwayomi
/// has no related/similar source query (what Komikku uses there), so this
/// reuses the tracker engine instead; completed results can show immediately.
@riverpod
AsyncValue<List<Recommendation>> mangaRecommendations(Ref ref, int mangaId) {
  final setup = ref.watch(recommendationSetupProvider(mangaId));
  if (setup.isLoading) return const AsyncLoading();
  if (setup.hasError) return AsyncError(setup.error!, setup.stackTrace!);
  final context = setup.value;
  if (context == null) return const AsyncData([]);
  final results = [
    for (final provider in context.providers)
      ref.watch(providerRecommendationsProvider(mangaId, provider.key)),
  ];
  final seen = <String>{};
  final recommendations = [
    for (final result in results)
      for (final recommendation in result.value ?? const <Recommendation>[])
        if (seen.add(recommendation.sourceUrl ?? recommendation.title))
          recommendation,
  ];
  if (recommendations.isEmpty && results.any((result) => result.isLoading)) {
    return const AsyncLoading();
  }
  if (recommendations.isEmpty) {
    for (final result in results) {
      if (result.hasError) return AsyncError(result.error!, result.stackTrace!);
    }
  }
  return AsyncData(recommendations);
}

/// One provider's recommendations for [mangaId]; each screen section watches
/// its own so they load, error, and empty independently (Komikku's per-source
/// RecommendationItemResult).
///
/// A successful pull is cached, so a later failure serves the last-good list
/// instead of an error.
@Riverpod(retry: _noRecommendationRetry)
Future<List<Recommendation>> providerRecommendations(
  Ref ref,
  int mangaId,
  String providerKey,
) async {
  final authType = ref.watch(authTypeKeyProvider) ?? AuthType.none;
  final address = Uri.parse(ref.watch(currentServerAddressProvider));
  final path =
      Uri.tryParse(ref.watch(serverUrlProvider) ?? '')?.normalizePath().path ??
      '';
  final server = Uri(
    scheme: address.scheme,
    host: address.host,
    port: address.port,
    path: path.replaceFirst(RegExp(r'/+$'), ''),
  ).toString();
  final binding = authType == AuthType.uiLogin
      ? (await ref.watch(authCredentialsStoreProvider.future)).accountBinding
      : null;
  final scope = authType == AuthType.uiLogin
      ? binding == null
            ? null
            : ['catalog', binding.catalogId, binding.userId]
      : ['server', server, authType.name];
  final setup = await ref.watch(recommendationSetupProvider(mangaId).future);
  if (setup == null) return const [];
  final provider = setup.providers.firstWhere((p) => p.key == providerKey);
  final prefs = ref.read(sharedPreferencesProvider);
  final lookupId = provider is TrackerRecommendationProvider
      ? setup.ctx.remoteIdByTracker[provider.trackerKey]
      : null;
  final cacheKey = scope == null
      ? null
      : 'recsCache:v3:${jsonEncode([scope, mangaId, setup.ctx.title, providerKey, lookupId])}';
  try {
    final recs = await provider
        .fetch(setup.ctx)
        .timeout(const Duration(seconds: 30));
    // Komikku de-dupes each source's list by url.
    final seen = <String>{};
    final deduped = [
      for (final r in recs)
        if (seen.add(r.sourceUrl ?? r.title)) r,
    ];
    if (deduped.isNotEmpty && cacheKey != null) {
      await prefs.setString(
        cacheKey,
        jsonEncode([for (final r in deduped) r.toJson()]),
      );
    }
    return deduped;
  } catch (_) {
    final cached = cacheKey == null ? null : prefs.getString(cacheKey);
    if (cached != null) {
      return [
        for (final j in jsonDecode(cached) as List)
          Recommendation.fromJson(j as Map<String, dynamic>),
      ];
    }
    rethrow;
  }
}
