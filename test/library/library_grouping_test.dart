// Tests for the pure groupLibrary() function.
// No GraphQL, no providers — just lightweight fake data.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/library_group.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_grouping.dart';

// ───────────────────────── fakes ─────────────────────────

/// Minimal stand-in for MangaDto for pure grouping tests.
class _Manga {
  final int id;
  final String sourceId;
  final String sourceName;
  final String sourceLang;
  final String status;
  final List<int> categoryIds;
  final List<String> tags;

  const _Manga({
    required this.id,
    this.sourceId = 'src1',
    this.sourceName = 'Source 1',
    this.sourceLang = 'en',
    this.status = 'ONGOING',
    this.categoryIds = const [],
    this.tags = const [],
  });
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

MangaProxy _proxy(_Manga m) => (
  id: m.id,
  sourceId: m.sourceId,
  sourceName: m.sourceName,
  sourceLang: m.sourceLang,
  status: m.status,
  categoryIds: m.categoryIds,
  trackStatuses: const [],
  tags: m.tags,
);

CategoryProxy _catProxy(_Category c) => (id: c.id, name: c.name);

// ──────────────────────── tests ──────────────────────────

void main() {
  group('groupLibrary — BY_SOURCE', () {
    test('buckets manga by sourceId', () {
      final mangas = [
        _proxy(
          _Manga(id: 1, sourceId: 'a', sourceName: 'Zebra', sourceLang: 'en'),
        ),
        _proxy(
          _Manga(id: 2, sourceId: 'b', sourceName: 'Alpha', sourceLang: 'en'),
        ),
        _proxy(
          _Manga(id: 3, sourceId: 'a', sourceName: 'Zebra', sourceLang: 'en'),
        ),
      ];
      final tabs = groupLibrary(mangas, LibraryGroup.bySource, []);
      // Two distinct sources
      expect(tabs.length, 2);
      // Each manga is in exactly one tab
      final allIds = tabs.expand((t) => t.mangaIds).toList();
      expect(allIds..sort(), [1, 2, 3]..sort());
    });
  });

  group('groupLibrary — BY_STATUS', () {
    test('orders tabs by statusOrder', () {
      final mangas = [
        _proxy(_Manga(id: 1, status: 'UNKNOWN')),
        _proxy(_Manga(id: 2, status: 'COMPLETED')),
        _proxy(_Manga(id: 3, status: 'ONGOING')),
        _proxy(_Manga(id: 4, status: 'ON_HIATUS')),
      ];
      final tabs = groupLibrary(mangas, LibraryGroup.byStatus, []);
      expect(tabs.map((t) => t.name).toList(), [
        'Ongoing',
        'Completed',
        'On hiatus',
        'Unknown',
      ]);
    });
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

  group('groupLibrary — UNGROUPED', () {
    test('yields exactly one tab containing all manga', () {
      final mangas = [
        _proxy(_Manga(id: 1)),
        _proxy(_Manga(id: 2)),
        _proxy(_Manga(id: 3)),
      ];
      final tabs = groupLibrary(mangas, LibraryGroup.ungrouped, []);
      expect(tabs.length, 1);
      expect(tabs.single.mangaIds..sort(), [1, 2, 3]);
    });
  });

  group('groupLibrary — BY_TAG', () {
    test('fans a manga out across every tag it carries', () {
      final mangas = [
        _proxy(_Manga(id: 1, tags: ['Action', 'Romance'])),
        _proxy(_Manga(id: 2, tags: ['Action'])),
      ];
      final tabs = groupLibrary(mangas, LibraryGroup.byTag, []);
      final byName = {for (final t in tabs) t.name: t.mangaIds};
      expect(byName['Action']!..sort(), [1, 2]);
      expect(byName['Romance'], [1]);
    });
  });

  group('groupLibrary — BY_LANGUAGE', () {
    test('buckets by source language, labelled with flag + name', () {
      final mangas = [
        _proxy(_Manga(id: 1, sourceLang: 'ja')),
        _proxy(_Manga(id: 2, sourceLang: 'en')),
        _proxy(_Manga(id: 3, sourceLang: 'ja')),
      ];
      final tabs = groupLibrary(mangas, LibraryGroup.byLanguage, []);
      // Sorted by DISPLAY name: English before Japanese (not en/ja by code).
      expect(tabs.map((t) => t.name).toList(), [
        '🇺🇸 English',
        '🇯🇵 Japanese',
      ]);
      expect(tabs.first.mangaIds, [2]);
      expect(tabs.last.mangaIds..sort(), [1, 3]);
    });
  });
}
