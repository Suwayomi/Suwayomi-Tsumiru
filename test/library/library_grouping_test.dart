// Tests for the pure groupLibrary() function.
// No GraphQL, no providers — just lightweight fake data.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/library_group.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_grouping.dart';

// ───────────────────────── fakes ─────────────────────────

/// Minimal stand-in for MangaDto for pure grouping tests.
class _Manga {
  final int id;
  final List<int> categoryIds;

  const _Manga({required this.id, this.categoryIds = const []});
}

/// Minimal stand-in for CategoryDto.
class _Category {
  final int id;
  final String name;

  const _Category({required this.id, required this.name});
}

// Adapters so the fake types satisfy the groupLibrary signature
// (which works on duck-typed records from this test context).
// We use the real groupLibrary via the exported MangaProxy / CategoryProxy
// typedefs, but for this test we define local helpers.

MangaProxy _proxy(
  _Manga m, {
  List<({int trackerId, int status})> trackStatuses = const [],
}) => (
  id: m.id,
  sourceId: 'src1',
  sourceName: 'Source 1',
  sourceLang: 'en',
  status: 'ONGOING',
  categoryIds: m.categoryIds,
  trackStatuses: trackStatuses,
  tags: const <String>[],
);

CategoryProxy _catProxy(_Category c) => (id: c.id, name: c.name);

// ──────────────────────── tests ──────────────────────────

void main() {
  test('groups tracker statuses by their shared meaning', () {
    final mangas = [
      _proxy(_Manga(id: 1), trackStatuses: [(trackerId: 1, status: 6)]),
      _proxy(_Manga(id: 2), trackStatuses: [(trackerId: 1, status: 7)]),
      _proxy(_Manga(id: 3), trackStatuses: [(trackerId: 7, status: 0)]),
      _proxy(_Manga(id: 4), trackStatuses: [(trackerId: 11, status: 7)]),
      _proxy(_Manga(id: 5), trackStatuses: [(trackerId: 5, status: 3)]),
      _proxy(
        _Manga(id: 6),
        trackStatuses: [
          (trackerId: 1, status: 6),
          (trackerId: 2, status: 5),
        ],
      ),
      _proxy(_Manga(id: 7), trackStatuses: [(trackerId: 11, status: 3)]),
      _proxy(_Manga(id: 8), trackStatuses: [(trackerId: 7, status: 2)]),
      _proxy(_Manga(id: 9), trackStatuses: [(trackerId: 7, status: 3)]),
      _proxy(_Manga(id: 10)),
      _proxy(_Manga(id: 11), trackStatuses: [(trackerId: 5, status: 99)]),
      _proxy(_Manga(id: 12), trackStatuses: [(trackerId: 1, status: 99)]),
      _proxy(_Manga(id: 13), trackStatuses: [(trackerId: 99, status: 1)]),
    ];

    final tabs = groupLibrary(mangas, LibraryGroup.byTrackStatus, []);

    expect(
      tabs.map((tab) => tab.name).toList(),
      [
        'Reading',
        'Rereading',
        'Plan to read',
        'On hold',
        'Completed',
        'Dropped',
        'Other',
      ],
    );
    expect(
      tabs.map((tab) => tab.mangaIds).toList(),
      [
        [3, 5, 11],
        [2],
        [1, 4, 6],
        [7],
        [8],
        [9],
        [10, 12, 13],
      ],
    );
  });

  group('groupLibrary — BY_DEFAULT', () {
    test('fans a 2-category manga into both tabs', () {
      final cats = [
        _catProxy(_Category(id: 1, name: 'Favorites')),
        _catProxy(_Category(id: 2, name: 'Reading')),
      ];
      final mangas = [
        _proxy(_Manga(id: 99, categoryIds: [1, 2])),
      ];
      final tabs = groupLibrary(mangas, LibraryGroup.byDefault, cats);
      // Should appear in both cat 1 and cat 2 tabs
      final tabWithCat1 = tabs.firstWhere((t) => t.id == 1);
      final tabWithCat2 = tabs.firstWhere((t) => t.id == 2);
      expect(tabWithCat1.mangaIds, contains(99));
      expect(tabWithCat2.mangaIds, contains(99));
    });
  });
}
