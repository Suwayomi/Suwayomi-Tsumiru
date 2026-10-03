import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

MangaDto _manga({int unread = 3, String? age, String? chaptersAge}) =>
    Fragment$MangaDto(
      id: 7,
      title: 'M7',
      age: age,
      chaptersAge: chaptersAge,
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 10),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '1',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords: Fragment$MangaDto$trackRecords(
        totalCount: 0,
        nodes: const [],
      ),
      unreadCount: unread,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/7',
    );

void main() {
  test('an unchanged series does not reload the library', () {
    // `age` and `chaptersAge` tick with the clock, not with the series.
    expect(
      libraryEntryOutdated(
        _manga(age: '100', chaptersAge: '50'),
        _manga(age: '160', chaptersAge: '110'),
      ),
      isFalse,
    );
  });

  test('a change the library shows reloads it', () {
    expect(libraryEntryOutdated(_manga(), _manga(unread: 2)), isTrue);
  });

  test('a series missing on either side reloads it', () {
    expect(libraryEntryOutdated(null, _manga()), isTrue);
    expect(libraryEntryOutdated(_manga(), null), isTrue);
  });
}
