import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/download_ahead.dart';

import 'reader_test_fixtures.dart';

void main() {
  test(
    'download ahead follows the effective reader sequence in either direction',
    () {
      final current = testChapter(id: 1);
      final downloaded = current.copyWith.call(
        user: current.user.copyWith.call(isDownloaded: true),
      );
      final next = testChapter(
        id: 3,
      ).copyWith.call(user: current.user.copyWith.call(isDownloaded: true));
      final later = testChapter(id: 5);
      for (final chapters in [
        [downloaded, next, later],
        [later, next, downloaded],
      ]) {
        expect(
          chapterIdsForDownloadAhead(
            chapter: downloaded,
            chapters: chapters,
            nextChapter: next,
            pageIndex: 1,
            limit: 2,
            queued: {},
          ),
          [5],
        );
      }
    },
  );
}
