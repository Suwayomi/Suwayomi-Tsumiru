// Tests for the lewd and category filter paths in applyLibraryFilterSort().
// Uses the real Fragment$MangaDto constructors (no mocking needed — they are
// plain data classes with no side-effects or platform dependencies).

// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

// ─────────────────────────── helpers ────────────────────────────

Fragment$SourceDto _source({required bool isNsfw}) => Fragment$SourceDto(
      displayName: 'Test Source',
      iconUrl: '',
      id: '1',
      isConfigurable: false,
      isNsfw: isNsfw,
      lang: 'en',
      name: 'Test Source',
      supportsLatest: false,
      meta: const [],
      $extension: Fragment$SourceDto$extension(pkgName: 'test.pkg'),
    );

Fragment$MangaDto$categories _cats(List<int> ids) =>
    Fragment$MangaDto$categories(
      nodes: ids
          .map((id) => Fragment$MangaDto$categories$nodes(id: id))
          .toList(),
    );

Fragment$MangaDto _manga({
  required int id,
  Fragment$SourceDto? source,
  List<int> categoryIds = const [],
  int unreadCount = 0,
  int downloadCount = 0,
  int bookmarkCount = 0,
  bool started = false,
  String status = 'ONGOING',
  List<String> genre = const [],
}) =>
    Fragment$MangaDto(
      id: id,
      title: 'Manga $id',
      bookmarkCount: bookmarkCount,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: downloadCount,
      genre: genre,
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      source: source,
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: _cats(categoryIds),
      trackRecords: Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: unreadCount,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: 'https://example.com/manga/$id',
    );

/// Calls applyLibraryFilterSort with all defaults off/null and returns ids.
List<int> _filter(
  List<Fragment$MangaDto> input, {
  bool? lewd,
  bool filterCategories = false,
  Set<String> include = const {},
  Set<String> exclude = const {},
  bool filterTags = false,
  Set<String> tagsInclude = const {},
  Set<String> tagsExclude = const {},
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
      mangaFilterLewd: lewd,
      mangaFilterMinRating: 0,
      filterCategories: filterCategories,
      filterCategoriesInclude: include,
      filterCategoriesExclude: exclude,
      filterTags: filterTags,
      filterTagsInclude: tagsInclude,
      filterTagsExclude: tagsExclude,
      sortedBy: MangaSort.alphabetical,
      sortedDirection: true,
    ).map((m) => m.id).toList();

// ────────────────────────── tests ───────────────────────────────

void main() {
  final nsfw = _manga(id: 1, source: _source(isNsfw: true));
  final sfw = _manga(id: 2, source: _source(isNsfw: false));
  final noSource = _manga(id: 3); // source == null → treated as non-nsfw

  group('Lewd filter (mangaFilterLewd)', () {
    test('null → no filtering, all pass', () {
      final ids = _filter([nsfw, sfw, noSource], lewd: null);
      expect(ids, containsAll([1, 2, 3]));
    });

    test('true → only NSFW sources pass', () {
      final ids = _filter([nsfw, sfw, noSource], lewd: true);
      expect(ids, [1]);
    });

    test('false → only non-NSFW (or no-source) pass', () {
      final ids = _filter([nsfw, sfw, noSource], lewd: false);
      expect(ids, containsAll([2, 3]));
      expect(ids, isNot(contains(1)));
    });
  });

  group('Category include/exclude filter', () {
    final inCat2 = _manga(id: 10, categoryIds: [2]);
    final inCat3 = _manga(id: 11, categoryIds: [3]);
    final inCat23 = _manga(id: 12, categoryIds: [2, 3]);
    final noCat = _manga(id: 13);

    test('filterCategories false → no filtering even with sets', () {
      final ids = _filter(
        [inCat2, inCat3, inCat23, noCat],
        filterCategories: false,
        include: {'2'},
      );
      expect(ids, containsAll([10, 11, 12, 13]));
    });

    test('include {2} → only manga in cat 2 pass', () {
      final ids = _filter(
        [inCat2, inCat3, inCat23, noCat],
        filterCategories: true,
        include: {'2'},
      );
      expect(ids, containsAll([10, 12]));
      expect(ids, isNot(contains(11)));
      expect(ids, isNot(contains(13)));
    });

    test('exclude {3} → manga in cat 3 are dropped', () {
      final ids = _filter(
        [inCat2, inCat3, inCat23, noCat],
        filterCategories: true,
        exclude: {'3'},
      );
      expect(ids, containsAll([10, 13]));
      expect(ids, isNot(contains(11)));
      expect(ids, isNot(contains(12)));
    });

    test('include {2} exclude {3} → must be in 2, must not be in 3', () {
      // inCat2 (id 10): in 2, not in 3 → PASS
      // inCat3 (id 11): not in 2 → FAIL (include gate)
      // inCat23 (id 12): in 2 BUT also in 3 → FAIL (exclude gate)
      // noCat (id 13): not in 2 → FAIL
      final ids = _filter(
        [inCat2, inCat3, inCat23, noCat],
        filterCategories: true,
        include: {'2'},
        exclude: {'3'},
      );
      expect(ids, [10]);
    });

    test('empty include + empty exclude → all pass when filterCategories true', () {
      final ids = _filter(
        [inCat2, inCat3, noCat],
        filterCategories: true,
        include: {},
        exclude: {},
      );
      expect(ids, containsAll([10, 11, 13]));
    });
  });

  group('Tag filter (source genres + custom tags, case-insensitive)', () {
    final action = _manga(id: 20, genre: ['Action', 'Seinen']);
    final romance = _manga(id: 21, genre: ['Romance']);
    final actionLower = _manga(id: 22, genre: ['action']); // different casing

    test('filterTags false → no filtering even with a selection', () {
      final ids = _filter([action, romance], tagsInclude: {'Action'});
      expect(ids, containsAll([20, 21]));
    });

    test('include matches regardless of case', () {
      final ids = _filter([action, romance, actionLower],
          filterTags: true, tagsInclude: {'action'});
      expect(ids, [20, 22]);
    });

    test('include is OR across selected tags', () {
      final ids = _filter([action, romance],
          filterTags: true, tagsInclude: {'seinen', 'romance'});
      expect(ids, containsAll([20, 21]));
    });

    test('exclude drops matching manga, case-insensitively', () {
      final ids = _filter([action, romance, actionLower],
          filterTags: true, tagsExclude: {'Action'});
      expect(ids, [21]);
    });
  });
}
