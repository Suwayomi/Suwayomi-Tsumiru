import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/domain/duplicate_entry_mapper.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';

import '../manga_book/reader/reader_test_fixtures.dart';

Fragment$MangaDto$trackRecords$nodes _node({
  int trackerId = 1,
  String remoteId = '42',
  String title = 'Solo Leveling',
}) => Fragment$MangaDto$trackRecords$nodes(
  id: 1,
  trackerId: trackerId,
  remoteId: remoteId,
  status: 1,
  score: 0,
  title: title,
);

void main() {
  test('trackRecords nodes map to tracker pairs', () {
    final manga = testManga().copyWith.call(
      trackRecords: Fragment$MangaDto$trackRecords(
        totalCount: 2,
        nodes: [
          _node(trackerId: 1, remoteId: '42', title: 'Solo Leveling'),
          _node(trackerId: 2, remoteId: '99', title: 'Only I Level Up'),
        ],
      ),
    );

    final entry = dupEntryFromManga(manga);

    expect(entry.id, manga.id);
    expect(entry.title, manga.title);
    expect(entry.trackerPairs, [
      (trackerId: 1, remoteId: '42', remoteTitle: 'Solo Leveling'),
      (trackerId: 2, remoteId: '99', remoteTitle: 'Only I Level Up'),
    ]);
  });

  test('missing description is tolerated', () {
    final manga = testManga();
    expect(manga.description, isNull);

    final entry = dupEntryFromManga(manga);

    expect(entry.description, isNull);
  });

  test('empty trackRecords nodes (offline stub) map to empty pairs', () {
    final manga = testManga();
    expect(manga.trackRecords.nodes, isEmpty);

    final entry = dupEntryFromManga(manga);

    expect(entry.trackerPairs, isEmpty);
  });
}
