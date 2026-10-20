// test/src/features/manga_book/domain/chapter/chapter_download_presets_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_download_presets.dart';

ChapterDownloadCandidate _ch(
  int id,
  double chapterNumber, {
  bool isRead = false,
  bool isDownloaded = false,
}) => ChapterDownloadCandidate(
  id: id,
  chapterNumber: chapterNumber,
  isRead: isRead,
  isDownloaded: isDownloaded,
);

void main() {
  group('chaptersToQueueForPreset', () {
    test(
      'nextChapter returns first non-downloaded chapter after read position',
      () {
        final result = chaptersToQueueForPreset([
          _ch(101, 1, isRead: true),
          _ch(102, 2, isRead: true),
          _ch(103, 3),
          _ch(104, 4),
        ], DownloadPreset.nextChapter);
        expect(result, [103]);
      },
    );

    test('next5 takes 5 non-downloaded chapters after read position', () {
      final result = chaptersToQueueForPreset([
        for (var i = 1; i <= 10; i++) _ch(100 + i, i.toDouble()),
      ], DownloadPreset.next5);
      expect(result, [101, 102, 103, 104, 105]);
    });

    test('next10 / next25 use the right N', () {
      final ten = chaptersToQueueForPreset([
        for (var i = 1; i <= 30; i++) _ch(100 + i, i.toDouble()),
      ], DownloadPreset.next10);
      expect(ten.length, 10);
      expect(ten.first, 101);
      expect(ten.last, 110);

      final twentyFive = chaptersToQueueForPreset([
        for (var i = 1; i <= 30; i++) _ch(100 + i, i.toDouble()),
      ], DownloadPreset.next25);
      expect(twentyFive.length, 25);
      expect(twentyFive.last, 125);
    });

    test('unread returns all not-read non-downloaded chapters ascending', () {
      final result = chaptersToQueueForPreset([
        _ch(101, 1, isRead: true),
        _ch(102, 2),
        _ch(103, 3, isDownloaded: true),
        _ch(104, 4),
      ], DownloadPreset.unread);
      expect(result, [102, 104]);
    });

    test(
      'all returns every non-downloaded chapter ascending, regardless of read state',
      () {
        final result = chaptersToQueueForPreset([
          _ch(101, 1, isRead: true),
          _ch(102, 2),
          _ch(103, 3, isDownloaded: true),
        ], DownloadPreset.all);
        expect(result, [101, 102]);
      },
    );

    test('result is sorted by chapterNumber, not input order', () {
      final result = chaptersToQueueForPreset([
        _ch(105, 5),
        _ch(101, 1),
        _ch(103, 3),
      ], DownloadPreset.all);
      expect(result, [101, 103, 105]);
    });
  });
}
