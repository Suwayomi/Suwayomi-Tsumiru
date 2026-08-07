// Regression tests: a chapter absent from the filtered list (e.g. unread-only
// filter while re-reading) must resolve to NO neighbours, not an arbitrary one.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

ChapterDto _chapter({required int id, required String name, int sourceOrder = 0}) =>
    Fragment$ChapterDto(
      chapterNumber: 0,
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
      uploadDate: '0',
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

void main() {
  final chapters = [
    _chapter(id: 1, name: 'One', sourceOrder: 1),
    _chapter(id: 2, name: 'Two', sourceOrder: 2),
    _chapter(id: 3, name: 'Three', sourceOrder: 3),
  ];

  test('a chapter absent from the filtered list has NO neighbours', () async {
    final c = await _container(chapters);
    final pair = c.read(getNextAndPreviousChaptersProvider(
      mangaId: 1,
      chapterId: 9999,
    ));
    expect(pair, isNotNull);
    // Before the fix, indexWhere == -1 resolved one side to filteredList[0].
    expect(pair!.first, isNull);
    expect(pair.second, isNull);
  });

  test('a middle chapter resolves both neighbours', () async {
    final c = await _container(chapters);
    final pair = c.read(getNextAndPreviousChaptersProvider(
      mangaId: 1,
      chapterId: 2,
    ));
    expect(pair, isNotNull);
    expect(pair!.first, isNotNull);
    expect(pair.second, isNotNull);
  });

  test('an edge chapter resolves exactly one neighbour', () async {
    final c = await _container(chapters);
    final pair = c.read(getNextAndPreviousChaptersProvider(
      mangaId: 1,
      chapterId: 3,
    ));
    expect(pair, isNotNull);
    // One side present, one absent — never two, never zero for an in-list edge.
    expect([pair!.first, pair.second].where((e) => e != null).length, 1);
  });
}
