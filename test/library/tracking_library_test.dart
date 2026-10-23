// Tests for Task 8: per-tracker filter, tracker-score sort, by-track-status group.
//
// These tests are pure: no Flutter engine, no providers, no GraphQL.
// They import the domain logic directly.

// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/track_status.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

// ─────────────────────────── helpers ────────────────────────────

/// Build a minimal Fragment$MangaDto$trackRecords$nodes record.
Fragment$MangaDto$trackRecords$nodes _trackNode({
  required int trackerId,
  required int status,
  required double score,
}) => Fragment$MangaDto$trackRecords$nodes(
  id: 0,
  trackerId: trackerId,
  status: status,
  score: score,
  remoteId: '1',
  title: 'Title',
);

Fragment$MangaDto$trackRecords _trks(
  List<Fragment$MangaDto$trackRecords$nodes> nodes,
) => Fragment$MangaDto$trackRecords(nodes: nodes);

Fragment$MangaDto$categories _cats(List<int> ids) =>
    Fragment$MangaDto$categories(
      nodes: ids
          .map((id) => Fragment$MangaDto$categories$nodes(id: id))
          .toList(),
    );

Fragment$MangaDto _manga({
  required int id,
  List<Fragment$MangaDto$trackRecords$nodes> trackNodes = const [],
  int unreadCount = 0,
}) => Fragment$MangaDto(
  id: id,
  title: 'Manga $id',
  chapters: Fragment$MangaDto$chapters(totalCount: 0),
  genre: const [],
  initialized: true,
  meta: const [],
  source: null,
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: _cats(const []),
  trackRecords: _trks(trackNodes),
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: 'https://example.com/manga/$id',
  user: Fragment$MangaDto$user(
    bookmarkCount: 0,
    downloadCount: 0,
    inLibrary: true,
    inLibraryAt: '0',
    unreadCount: unreadCount,
  ),
);

// ─────────────────────────── tests ──────────────────────────────

void main() {
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
        meanNormalizedScore(
          m.trackRecords.nodes,
          trackerScales: {1: 10.0, 2: 100.0},
        ),
        closeTo(7.0, 0.001),
      );
    });
  });
}
