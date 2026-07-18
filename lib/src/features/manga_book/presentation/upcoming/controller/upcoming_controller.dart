// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../data/upcoming/graphql/__generated__/query.graphql.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../domain/next_update/next_update_predictor.dart';

part 'upcoming_controller.g.dart';

/// One day's worth of predicted releases.
class UpcomingGroup {
  const UpcomingGroup({required this.date, required this.mangas});

  /// Start-of-day for the predicted release.
  final DateTime date;
  final List<MangaDto> mangas;
}

/// The Upcoming screen's data: the grouped list (one [UpcomingGroup] per future
/// day, ascending) and the per-day counts the calendar paints as dots/badges.
class UpcomingData {
  const UpcomingData({required this.groups, required this.events});

  final List<UpcomingGroup> groups;
  final Map<DateTime, int> events;

  bool get isEmpty => groups.isEmpty;

  static const empty = UpcomingData(groups: [], events: {});
}

/// Pure grouping: bucket `(manga, predictedDate)` pairs into per-day groups
/// (today onward, ascending) plus the per-day count map. Testable in isolation.
UpcomingData buildUpcomingData(
  List<({MangaDto manga, DateTime date})> entries, {
  required DateTime today,
}) {
  final todayStart = DateTime(today.year, today.month, today.day);
  final byDate = <DateTime, List<MangaDto>>{};
  for (final e in entries) {
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    if (d.isBefore(todayStart)) continue; // upcoming only
    (byDate[d] ??= []).add(e.manga);
  }
  final dates = byDate.keys.toList()..sort();
  return UpcomingData(
    groups: [for (final d in dates) UpcomingGroup(date: d, mangas: byDate[d]!)],
    events: {for (final d in dates) d: byDate[d]!.length},
  );
}

/// Every manga in the library (across all categories), in one query.
@riverpod
Future<List<MangaDto>> upcomingLibraryMangas(Ref ref) async {
  final nodes = await ref
      .watch(graphQlClientProvider)
      .query$GetLibraryMangas(Options$Query$GetLibraryMangas())
      .getData((data) => data.mangas.nodes);
  return [for (final n in nodes ?? const []) n as MangaDto];
}

/// Predicts the next release for every (non-completed) library series from its
/// own chapter history and groups them by date. Chapter lists are loaded in
/// bounded-concurrency batches so a large library doesn't open N sockets at
/// once. Reuses the same [predictNextUpdate] the manga-details estimate uses.
@riverpod
Future<UpcomingData> upcoming(Ref ref) async {
  // Read before the await: this provider auto-disposes and touching ref after
  // the async gap throws UnmountedRefException.
  final client = ref.watch(graphQlClientProvider);
  final mangas = await ref.watch(upcomingLibraryMangasProvider.future);
  final now = DateTime.now();

  final entries = <({MangaDto manga, DateTime date})>[];
  const batchSize = 8;
  for (var i = 0; i < mangas.length; i += batchSize) {
    final batch = mangas.sublist(i, math.min(i + batchSize, mangas.length));
    final results = await Future.wait(batch.map((m) async {
      if (m.status == Enum$MangaStatus.COMPLETED) return null;
      try {
        final nodes = await client
            .query$RecentChapterDates(Options$Query$RecentChapterDates(
                variables:
                    Variables$Query$RecentChapterDates(mangaId: m.id)))
            .getData((d) => d.chapters.nodes);
        if (nodes == null || nodes.isEmpty) return null;
        final releases = <ChapterRelease>[
          for (final c in nodes)
            (
              uploadMs: int.tryParse(c.uploadDate) ?? 0,
              fetchMs: int.tryParse(c.fetchedAt) ?? 0,
            ),
        ];
        final next = predictNextUpdate(releases, now: now).nextUpdate;
        if (next == null) return null;
        return (manga: m, date: next);
      } catch (_) {
        return null;
      }
    }));
    entries.addAll(
        results.whereType<({MangaDto manga, DateTime date})>());
  }
  return buildUpcomingData(entries, today: now);
}
