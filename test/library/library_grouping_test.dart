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

MangaProxy _proxy(_Manga m) => (
  id: m.id,
  sourceId: 'src1',
  sourceName: 'Source 1',
  sourceLang: 'en',
  status: 'ONGOING',
  categoryIds: m.categoryIds,
  trackStatuses: const [],
  tags: const <String>[],
);

CategoryProxy _catProxy(_Category c) => (id: c.id, name: c.name);

// ──────────────────────── tests ──────────────────────────

void main() {
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
