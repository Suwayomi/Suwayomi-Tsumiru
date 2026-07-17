// Tests for the chapter sort modes in mangaChapterListWithFilter().
// Uses the real Fragment$ChapterDto constructor (plain data class) and a fake
// chapter-list notifier so no repository/network is involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

ChapterDto _chapter({
  required int id,
  required String name,
  int sourceOrder = 0,
  String uploadDate = '0',
}) =>
    Fragment$ChapterDto(
      chapterNumber: id.toDouble(),
      fetchedAt: '0',
      id: id,
      isBookmarked: false,
      isDownloaded: false,
      isRead: false,
      lastPageRead: 0,
      lastReadAt: '0',
      mangaId: 1,
      name: name,
      pageCount: 0,
      sourceOrder: sourceOrder,
      uploadDate: uploadDate,
      url: '',
      meta: const [],
    );

class _FakeChapterList extends MangaChapterList {
  _FakeChapterList(this.chapters);
  final List<ChapterDto> chapters;

  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => chapters;
}

Future<ProviderContainer> _container(List<ChapterDto> chapters) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      mangaChapterListProvider(mangaId: 1)
          .overrideWith(() => _FakeChapterList(chapters)),
    ],
  );
  addTearDown(c.dispose);
  await c.read(mangaChapterListProvider(mangaId: 1).future);
  return c;
}

List<String> _names(ProviderContainer c) =>
    (c.read(mangaChapterListWithFilterProvider(mangaId: 1)).value ?? [])
        .map((ch) => ch.name)
        .toList();

void main() {
  final chapters = [
    _chapter(id: 1, name: 'Gamma', sourceOrder: 1, uploadDate: '300'),
    _chapter(id: 2, name: 'alpha', sourceOrder: 2, uploadDate: '100'),
    _chapter(id: 3, name: 'Beta', sourceOrder: 3, uploadDate: '200'),
  ];

  test('default sort is by source order, newest (descending) first', () async {
    final c = await _container(chapters);
    expect(_names(c), ['Beta', 'alpha', 'Gamma']);
  });

  test('alphabetical sort is case-insensitive on chapter name', () async {
    final c = await _container(chapters);
    c.read(mangaChapterSortProvider.notifier).update(ChapterSort.alphabetical);
    c.read(mangaChapterSortDirectionProvider.notifier).update(true);
    expect(_names(c), ['alpha', 'Beta', 'Gamma']);
  });

  test('alphabetical sort respects descending direction', () async {
    final c = await _container(chapters);
    c.read(mangaChapterSortProvider.notifier).update(ChapterSort.alphabetical);
    c.read(mangaChapterSortDirectionProvider.notifier).update(false);
    expect(_names(c), ['Gamma', 'Beta', 'alpha']);
  });

  test('upload date sort still orders numerically', () async {
    final c = await _container(chapters);
    c.read(mangaChapterSortProvider.notifier).update(ChapterSort.uploadDate);
    c.read(mangaChapterSortDirectionProvider.notifier).update(true);
    expect(_names(c), ['alpha', 'Beta', 'Gamma']);
  });
}
