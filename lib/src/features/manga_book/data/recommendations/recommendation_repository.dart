// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../global_providers/global_providers.dart';
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

/// The recommendation context (title, tracker remote ids, source) for [mangaId]
/// plus the providers that apply to it. Built once and shared by every section.
@riverpod
Future<({RecommendationContext ctx, List<RecommendationProvider> providers})?>
    recommendationSetup(Ref ref, int mangaId) async {
  final manga = await ref.watch(mangaWithIdProvider(mangaId: mangaId).future);
  final title = manga?.title;
  if (manga == null || title == null || title.isEmpty) return null;

  final trackers = await ref.watch(trackersProvider.future);
  final nameById = {for (final t in trackers) t.id: t.name.toLowerCase()};
  final remoteIdByTracker = <String, String>{};
  for (final rec in manga.trackRecords.nodes) {
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
/// reuses the tracker engine instead; a failing provider just drops out.
@riverpod
Future<List<Recommendation>> mangaRecommendations(Ref ref, int mangaId) async {
  final setup = await ref.watch(recommendationSetupProvider(mangaId).future);
  if (setup == null) return const [];
  final lists = await Future.wait([
    for (final p in setup.providers)
      ref
          .watch(providerRecommendationsProvider(mangaId, p.key).future)
          .catchError((_) => const <Recommendation>[]),
  ]);
  final seen = <String>{};
  return [
    for (final list in lists)
      for (final r in list)
        if (seen.add(r.sourceUrl ?? r.title)) r,
  ];
}

/// One provider's recommendations for [mangaId]; each screen section watches
/// its own so they load, error, and empty independently (Komikku's per-source
/// RecommendationItemResult).
///
/// A successful pull is cached, so a later failure serves the last-good list
/// instead of an error.
@riverpod
Future<List<Recommendation>> providerRecommendations(
  Ref ref,
  int mangaId,
  String providerKey,
) async {
  final setup = await ref.watch(recommendationSetupProvider(mangaId).future);
  if (setup == null) return const [];
  final provider = setup.providers.firstWhere((p) => p.key == providerKey);
  final prefs = ref.read(sharedPreferencesProvider);
  final cacheKey = 'recsCache:$mangaId:$providerKey';
  try {
    final recs = await provider.fetch(setup.ctx);
    // Komikku de-dupes each source's list by url.
    final seen = <String>{};
    final deduped = [
      for (final r in recs)
        if (seen.add(r.sourceUrl ?? r.title)) r,
    ];
    if (deduped.isNotEmpty) {
      await prefs.setString(
        cacheKey,
        jsonEncode([for (final r in deduped) r.toJson()]),
      );
    }
    return deduped;
  } catch (_) {
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      return [
        for (final j in jsonDecode(cached) as List)
          Recommendation.fromJson(j as Map<String, dynamic>),
      ];
    }
    rethrow;
  }
}
