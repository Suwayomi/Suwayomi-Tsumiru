// Tests for Task 8: per-tracker filter, tracker-score sort, by-track-status group.
//
// These tests are pure: no Flutter engine, no providers, no GraphQL.
// They import the domain logic directly.

// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/domain/library_group.dart';
import 'package:tsumiru/src/features/library/domain/track_status.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_grouping.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

// ─────────────────────────── helpers ────────────────────────────

/// Build a minimal Fragment$MangaDto$trackRecords$nodes record.
Fragment$MangaDto$trackRecords$nodes _trackNode({
  required int trackerId,
  required int status,
  required double score,
}) =>
    Fragment$MangaDto$trackRecords$nodes(
      id: 0,
      trackerId: trackerId,
      status: status,
      score: score,
    );

Fragment$MangaDto$trackRecords _trks(
    List<Fragment$MangaDto$trackRecords$nodes> nodes) =>
    Fragment$MangaDto$trackRecords(totalCount: nodes.length, nodes: nodes);

Fragment$MangaDto$categories _cats(List<int> ids) =>
    Fragment$MangaDto$categories(
      nodes: ids.map((id) => Fragment$MangaDto$categories$nodes(id: id)).toList(),
    );

Fragment$MangaDto _manga({
  required int id,
  List<Fragment$MangaDto$trackRecords$nodes> trackNodes = const [],
  int unreadCount = 0,
}) =>
    Fragment$MangaDto(
      id: id,
      title: 'Manga $id',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      source: null,
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: _cats(const []),
      trackRecords: _trks(trackNodes),
      unreadCount: unreadCount,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: 'https://example.com/manga/$id',
    );

/// Calls applyLibraryFilterSort with all defaults off/null, returning ordered ids.
List<int> _apply(
  List<Fragment$MangaDto> input, {
  MangaSort sortedBy = MangaSort.trackerScore,
  bool sortedDirection = true,
  Map<int, double> trackerScales = const {},
  Map<int, bool?> trackerFilters = const {},
}) =>
    applyLibraryFilterSort(
      input,
      query: null,
      mangaFilterUnread: null,
      mangaFilterDownloaded: null,
      mangaFilterCompleted: null,
      mangaFilterStarted: null,
      mangaFilterBookmarked: null,
      mangaFilterOffline: null,
      offlineMangaIds: const {},
      mangaFilterLewd: null,
      mangaFilterMinRating: 0,
      filterCategories: false,
      filterCategoriesInclude: const {},
      filterCategoriesExclude: const {},
      filterTags: false,
      filterTagsInclude: const {},
      filterTagsExclude: const {},
      sortedBy: sortedBy,
      sortedDirection: sortedDirection,
      trackerScales: trackerScales,
      trackerFilters: trackerFilters,
    ).map((m) => m.id).toList();

// ─────────────────────────── tests ──────────────────────────────

void main() {
  // ───── normalizedScore ─────────────────────────────────────────

  group('normalizedScore', () {
    test('MAL 0-10: score 7 on scaleMax 10 → 7.0', () {
      expect(normalizedScore(score: 7.0, scaleMax: 10.0), closeTo(7.0, 0.001));
    });

    test('AniList 0-100: score 70 on scaleMax 100 → 7.0', () {
      expect(normalizedScore(score: 70.0, scaleMax: 100.0), closeTo(7.0, 0.001));
    });

    test('Kitsu 0-20: score 14 on scaleMax 20 → 7.0', () {
      expect(normalizedScore(score: 14.0, scaleMax: 20.0), closeTo(7.0, 0.001));
    });

    test('score 0 → 0.0 regardless of scale', () {
      expect(normalizedScore(score: 0.0, scaleMax: 10.0), closeTo(0.0, 0.001));
      expect(normalizedScore(score: 0.0, scaleMax: 100.0), closeTo(0.0, 0.001));
    });

    test('max score → 10.0', () {
      expect(normalizedScore(score: 10.0, scaleMax: 10.0), closeTo(10.0, 0.001));
      expect(normalizedScore(score: 100.0, scaleMax: 100.0), closeTo(10.0, 0.001));
    });

    test('MangaUpdates fractional scale 0–9.9: last label "9.9" → scaleMax 9.9', () {
      // Verifies the fix: scaleMax comes from last-label value, not list length.
      // 100 entries "0".."9.9" → last label "9.9" → scaleMax 9.9.
      // score 9.9 should normalize to exactly 10.0.
      expect(normalizedScore(score: 9.9, scaleMax: 9.9), closeTo(10.0, 0.001));
      // score 4.95 should normalize to ~5.0.
      expect(normalizedScore(score: 4.95, scaleMax: 9.9), closeTo(5.0, 0.001));
    });
  });

  // ───── meanNormalizedScore ─────────────────────────────────────

  group('meanNormalizedScore', () {
    test('mean across two trackers with different scales', () {
      // Tracker 1 (MAL, scale 10): score 8 → 8.0 normalized
      // Tracker 2 (AniList, scale 100): score 60 → 6.0 normalized
      // mean = 7.0
      final nodes = [
        _trackNode(trackerId: 1, status: 1, score: 8.0),
        _trackNode(trackerId: 2, status: 1, score: 60.0),
      ];
      final m = _manga(id: 1, trackNodes: nodes);
      expect(
        meanNormalizedScore(m.trackRecords.nodes,
            trackerScales: {1: 10.0, 2: 100.0}),
        closeTo(7.0, 0.001),
      );
    });

    test('empty → -1.0 (untracked sentinel)', () {
      final m = _manga(id: 1);
      expect(
        meanNormalizedScore(m.trackRecords.nodes, trackerScales: {}),
        -1.0,
      );
    });

    test('all-zero scores → 0.0', () {
      final nodes = [_trackNode(trackerId: 1, status: 1, score: 0.0)];
      final m = _manga(id: 1, trackNodes: nodes);
      expect(
        meanNormalizedScore(m.trackRecords.nodes, trackerScales: {1: 10.0}),
        closeTo(0.0, 0.001),
      );
    });
  });

  // ───── MangaSort.trackerScore ──────────────────────────────────

  group('MangaSort.trackerScore sort', () {
    test('ascending by mean normalized score', () {
      final mangas = [
        _manga(id: 1, trackNodes: [_trackNode(trackerId: 1, status: 1, score: 8.0)]),
        _manga(id: 2, trackNodes: [_trackNode(trackerId: 1, status: 1, score: 5.0)]),
        _manga(id: 3, trackNodes: [_trackNode(trackerId: 1, status: 1, score: 9.0)]),
      ];
      final ids = _apply(mangas,
          sortedBy: MangaSort.trackerScore,
          sortedDirection: true,
          trackerScales: {1: 10.0});
      expect(ids, [2, 1, 3]);
    });

    test('untracked sorts last in ascending direction', () {
      final tracked = _manga(
          id: 1, trackNodes: [_trackNode(trackerId: 1, status: 1, score: 3.0)]);
      final untracked = _manga(id: 2);
      final ids = _apply([untracked, tracked],
          sortedBy: MangaSort.trackerScore,
          sortedDirection: true,
          trackerScales: {1: 10.0});
      expect(ids.last, 2);
    });

    test('untracked sorts last in descending direction', () {
      final tracked = _manga(
          id: 1, trackNodes: [_trackNode(trackerId: 1, status: 1, score: 3.0)]);
      final untracked = _manga(id: 2);
      final ids = _apply([tracked, untracked],
          sortedBy: MangaSort.trackerScore,
          sortedDirection: false,
          trackerScales: {1: 10.0});
      expect(ids.last, 2);
    });
  });

  // ───── per-tracker filter ──────────────────────────────────────

  group('per-tracker filter', () {
    late Fragment$MangaDto withT1;
    late Fragment$MangaDto withT2;
    late Fragment$MangaDto noTracker;

    setUp(() {
      withT1 = _manga(
          id: 1, trackNodes: [_trackNode(trackerId: 1, status: 1, score: 5.0)]);
      withT2 = _manga(
          id: 2, trackNodes: [_trackNode(trackerId: 2, status: 1, score: 5.0)]);
      noTracker = _manga(id: 3);
    });

    test('true keeps only manga tracked by that tracker', () {
      final ids = _apply([withT1, withT2, noTracker],
          sortedBy: MangaSort.alphabetical, trackerFilters: {1: true});
      expect(ids, [1]);
    });

    test('false excludes manga tracked by that tracker', () {
      final ids = _apply([withT1, withT2, noTracker],
          sortedBy: MangaSort.alphabetical, trackerFilters: {1: false});
      expect(ids, containsAll([2, 3]));
      expect(ids, isNot(contains(1)));
    });

    test('null filter → no effect', () {
      final ids = _apply([withT1, withT2, noTracker],
          sortedBy: MangaSort.alphabetical, trackerFilters: {1: null});
      expect(ids, containsAll([1, 2, 3]));
    });

    test('empty map → all pass', () {
      final ids = _apply([withT1, withT2, noTracker],
          sortedBy: MangaSort.alphabetical, trackerFilters: {});
      expect(ids, containsAll([1, 2, 3]));
    });
  });

  // ───── BY_TRACK_STATUS grouping ───────────────────────────────

  group('groupLibrary — BY_TRACK_STATUS', () {
    test('manga with two status values fans into both buckets', () {
      final m1 = _manga(
        id: 1,
        trackNodes: [
          _trackNode(trackerId: 1, status: 1, score: 0),
          _trackNode(trackerId: 2, status: 2, score: 0),
        ],
      );
      final proxies = [mangaToProxy(m1)];
      final tabs = groupLibrary(proxies, LibraryGroup.byTrackStatus, []);

      final tab1 = tabs.where((t) => t.id == 1).firstOrNull;
      final tab2 = tabs.where((t) => t.id == 2).firstOrNull;
      expect(tab1, isNotNull, reason: 'status-1 tab should exist');
      expect(tab2, isNotNull, reason: 'status-2 tab should exist');
      expect(tab1!.mangaIds, contains(1));
      expect(tab2!.mangaIds, contains(1));
    });

    test('untracked manga goes to Other bucket', () {
      final m = _manga(id: 42);
      final proxies = [mangaToProxy(m)];
      final tabs = groupLibrary(proxies, LibraryGroup.byTrackStatus, []);

      final other = tabs.firstWhere(
        (t) => t.name == 'Other',
        orElse: () => throw StateError(
            'No Other tab found: ${tabs.map((t) => t.name).join(', ')}'),
      );
      expect(other.mangaIds, contains(42));
    });
  });
}
