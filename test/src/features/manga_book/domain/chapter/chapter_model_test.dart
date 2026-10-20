import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';

void main() {
  group('ChapterExtension.hasReadingProgress', () {
    test('is false for the server first-chapter fallback', () {
      expect(
        _chapter(
          isRead: false,
          lastPageRead: 0,
          lastReadAt: '0',
        ).hasReadingProgress,
        isFalse,
      );
    });
  });
}

ChapterDto _chapter({
  required bool isRead,
  required int lastPageRead,
  required String lastReadAt,
}) => ChapterDto(
  chapterNumber: 1,
  fetchedAt: '0',
  id: 1,
  isBookmarked: false,
  isDownloaded: false,
  isRead: isRead,
  lastPageRead: lastPageRead,
  lastReadAt: lastReadAt,
  mangaId: 1,
  name: 'Chapter 1',
  pageCount: 1,
  sourceOrder: 1,
  uploadDate: '0',
  url: '/chapter/1',
  meta: const [],
);
