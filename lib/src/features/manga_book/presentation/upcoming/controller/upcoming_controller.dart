// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../data/upcoming/graphql/__generated__/query.graphql.dart';
import '../../../data/updates/updates_repository.dart';
import '../../../domain/manga/manga_model.dart';
import '../../../domain/next_update/next_update_predictor.dart';

part 'upcoming_controller.g.dart';

enum UpcomingView { month, week }

@riverpod
class UpcomingViewNotifier extends _$UpcomingViewNotifier
    with SharedPreferenceEnumClientMixin<UpcomingView> {
  @override
  UpcomingView? build() => initialize(
    DBKeys.upcomingView,
    enumList: UpcomingView.values,
    initial: UpcomingView.week,
  );
}

@riverpod
class UpcomingShowPastReleasesNotifier
    extends _$UpcomingShowPastReleasesNotifier
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.upcomingShowPastReleases);
}

class UpcomingGroup {
  const UpcomingGroup({required this.date, required this.mangas});

  /// Start-of-day for the predicted release.
  final DateTime date;
  final List<MangaDto> mangas;
}

/// Future-day groups in ascending order, with per-day calendar counts.
class UpcomingData {
  const UpcomingData({required this.groups, required this.events});

  final List<UpcomingGroup> groups;
  final Map<DateTime, int> events;

  bool get isEmpty => groups.isEmpty;

  static const empty = UpcomingData(groups: [], events: {});
}

/// Groups today-or-later predictions by day in ascending order.
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

@riverpod
Future<List<MangaDto>> upcomingLibraryMangas(Ref ref) async {
  final nodes = await ref
      .watch(graphQlClientProvider)
      .query$GetLibraryMangas(
        Options$Query$GetLibraryMangas(
          variables: Variables$Query$GetLibraryMangas(
            withLibraryFields: false,
            withFirstUnread: false,
          ),
        ),
      )
      .getData((data) => data.mangas.nodes);
  return [for (final n in nodes ?? const []) n as MangaDto];
}

/// Predicts non-completed library series in bounded batches to limit concurrent chapter requests.
@riverpod
Future<UpcomingData> upcoming(Ref ref) async {
  // Capture before await; this autoDispose provider may be gone when the fetch completes.
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

typedef CalendarSeries = ({int id, String title, String? thumbnailUrl});

@riverpod
Future<Map<DateTime, List<CalendarSeries>>> upcomingPastReleases(
  Ref ref, {
  required DateTime start,
  required DateTime end,
}) async {
  final chapters = await ref
      .watch(updatesRepositoryProvider)
      .getChaptersInRange(start: start, end: end);
  final byDay = <DateTime, Map<int, CalendarSeries>>{};
  for (final chapter in chapters) {
    final seconds = int.tryParse(chapter.fetchedAt);
    if (seconds == null) continue;
    final fetched = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final day = DateTime(fetched.year, fetched.month, fetched.day);
    final manga = chapter.manga;
    (byDay[day] ??= {})[manga.id] = (
      id: manga.id,
      title: manga.title,
      thumbnailUrl: manga.thumbnailUrl,
    );
  }
  return {for (final day in byDay.entries) day.key: day.value.values.toList()};
}
