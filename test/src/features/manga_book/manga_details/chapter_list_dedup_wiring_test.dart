// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import 'chapter_test_helpers.dart';

class _FixedChapterList extends MangaChapterList {
  _FixedChapterList(this.chapters);
  final List<ChapterDto> chapters;
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => chapters;
}

class _FixedPreferredScanlators extends MangaPreferredScanlators {
  _FixedPreferredScanlators(this.groups);
  final List<String> groups;
  @override
  List<String> build({required int mangaId}) => groups;
}

class _FixedShowAll extends MangaShowAllScanlatorVersions {
  _FixedShowAll(this.value);
  final bool value;
  @override
  bool build({required int mangaId}) => value;
}

class _FixedUnreadFilter extends MangaChapterFilterUnread {
  _FixedUnreadFilter(this.value);
  final bool? value;
  @override
  bool? build() => value;
}

/// Fixed manga id 1 fixture:
/// number 1: A copy (id 1), B copy (id 2)
/// number 2: B copy only (id 3)
/// number 3: A copy read (id 4), B copy unread (id 5)
/// sourceOrder ascends with id (0..4) so the default descending-by-source
/// sort (DBKeys.chapterSortDirection.initial == false, i.e. dsc) resolves to
/// highest sourceOrder first, unambiguously.
final _chapters = [
  ch(id: 1, number: 1, scanlator: 'A', sourceOrder: 0),
  ch(id: 2, number: 1, scanlator: 'B', sourceOrder: 1),
  ch(id: 3, number: 2, scanlator: 'B', sourceOrder: 2),
  ch(id: 4, number: 3, scanlator: 'A', isRead: true, sourceOrder: 3),
  ch(id: 5, number: 3, scanlator: 'B', sourceOrder: 4),
];

Future<ProviderContainer> _container({
  List<ChapterDto>? chapters,
  List<String> preference = const [],
  bool showAll = false,
  bool offline = false,
  bool? unreadFilter,
  int? keepChapterId,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    mangaChapterListProvider(mangaId: 1)
        .overrideWith(() => _FixedChapterList(chapters ?? _chapters)),
    mangaPreferredScanlatorsProvider(mangaId: 1)
        .overrideWith(() => _FixedPreferredScanlators(preference)),
    mangaShowAllScanlatorVersionsProvider(mangaId: 1)
        .overrideWith(() => _FixedShowAll(showAll)),
    offlineActiveProvider.overrideWithValue(offline),
    if (unreadFilter != null)
      mangaChapterFilterUnreadProvider
          .overrideWith(() => _FixedUnreadFilter(unreadFilter)),
  ]);
  addTearDown(c.dispose);
  await c.read(mangaChapterListProvider(mangaId: 1).future);
  return c;
}

List<int> _ids(ProviderContainer c, {int? keepChapterId}) =>
    c
        .read(mangaChapterListWithFilterProvider(
            mangaId: 1, keepChapterId: keepChapterId))
        .value!
        .map((e) => e.id)
        .toList();

void main() {
  test('dedup runs before filters: unread filter sees aggregate state',
      () async {
    // preference ['B'], unread filter ON: ch3's B row aggregates isRead=true
    // from A's read copy (id 4) -> filtered OUT. Survivors: ch1-B(2), ch2-B(3).
    final c = await _container(preference: const ['B'], unreadFilter: true);
    expect(_ids(c), [3, 2]);
  });

  test('no preference -> identical to today (all copies)', () async {
    final c = await _container();
    expect(_ids(c), [5, 4, 3, 2, 1]);
  });

  test('show-all ON -> raw list passes through', () async {
    final c = await _container(preference: const ['B'], showAll: true);
    expect(_ids(c), [5, 4, 3, 2, 1]);
  });

  test('catalog-shaped rows (unique fabricated numbers) never collapse',
      () async {
    // The offline catalog fabricates chapterNumber from the list index, so
    // every row has a distinct number and dedup structurally no-ops — this is
    // the offline safety property (there is no offlineActive gate).
    final catalogShaped = [
      ch(id: 1, number: 0, scanlator: 'A', sourceOrder: 0),
      ch(id: 2, number: 1, scanlator: 'B', sourceOrder: 1),
      ch(id: 3, number: 2, scanlator: 'A', sourceOrder: 2),
      ch(id: 4, number: 3, scanlator: 'B', sourceOrder: 3),
    ];
    final c = await _container(
        chapters: catalogShaped, preference: const ['B'], offline: true);
    expect(_ids(c), [4, 3, 2, 1]);
  });

  test('keepChapterId surfaces a hidden copy', () async {
    // preference ['B'], keepChapterId = ch1-A's id (1) -> ch1's row is A's
    // copy instead of B's; ch2/ch3 dedup normally (B wins both).
    final c = await _container(preference: const ['B']);
    expect(_ids(c, keepChapterId: 1), [5, 3, 1]);
  });

  test('getNextAndPreviousChapters resolves neighbours from a hidden copy',
      () async {
    // n1: A(id 1) + B(id 2); n2: B(id 3) only. Preference ['B'] would
    // normally hide id 1 (A loses n1 to B), but the reader chain passes
    // its own chapterId as keepChapterId, forcing id 1 to win n1 instead
    // -> deduped chain is [id 1, id 3].
    final hiddenCopyChapters = [
      ch(id: 1, number: 1, scanlator: 'A', sourceOrder: 0),
      ch(id: 2, number: 1, scanlator: 'B', sourceOrder: 1),
      ch(id: 3, number: 2, scanlator: 'B', sourceOrder: 2),
    ];
    final c = await _container(
      chapters: hiddenCopyChapters,
      preference: const ['B'],
    );
    final pair = c.read(
      getNextAndPreviousChaptersProvider(mangaId: 1, chapterId: 1),
    );
    expect(pair, isNotNull);
    // Default sort is source-order descending (id 3 first, id 1 last), so
    // id 1's only neighbour (id 3) resolves as "first", not (null, null).
    expect(pair!.first?.id, 3);
    expect(pair.second, isNull);
  });

  test('bulk-actions list dedups but stays unfiltered', () async {
    final c = await _container(preference: const ['B']);
    final rows = c
        .read(mangaChapterListForBulkActionsProvider(mangaId: 1))
        .value!
        .map((e) => e.id)
        .toList();
    expect(rows, unorderedEquals([2, 3, 5]));
  });

  test('bulk-actions list is raw when show-all is on', () async {
    final c = await _container(preference: const ['B'], showAll: true);
    final rows = c
        .read(mangaChapterListForBulkActionsProvider(mangaId: 1))
        .value!
        .map((e) => e.id)
        .toList();
    expect(rows, unorderedEquals([1, 2, 3, 4, 5]));
  });
}
