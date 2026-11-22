// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/reader_page_offset.dart';

ChapterDto _chapter({
  bool isRead = false,
  int lastPageRead = 3,
  String? remote,
}) => Fragment$ChapterDto(
  chapterNumber: 1,
  fetchedAt: '0',
  id: 1,
  mangaId: 1,
  name: 'Chapter 1',
  pageCount: 10,
  sourceOrder: 1,
  uploadDate: '0',
  url: '/chapter/1',
  meta: [
    if (remote != null)
      Fragment$ChapterDto$meta(key: readerPageOffsetMetaKey, value: remote),
  ],
  user: Fragment$ChapterDto$user(
    isBookmarked: false,
    isDownloaded: false,
    isRead: isRead,
    lastPageRead: lastPageRead,
    lastReadAt: '0',
  ),
);

ReaderPageOffset _offset(int page, double fraction, int millis) =>
    ReaderPageOffset(
      page: page,
      fraction: fraction,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(millis),
    );

void main() {
  group('ReaderPageOffset codec', () {
    test('round-trips', () {
      final offset = _offset(3, 0.4215, 1000);
      expect(ReaderPageOffset.decode(offset.encode()), offset);
    });

    test('rejects malformed or out-of-range values', () {
      for (final raw in [null, '', '3:0.5', 'a:0.5:1', '3:1.5:1', '-1:0.5:1']) {
        expect(ReaderPageOffset.decode(raw), isNull, reason: '$raw');
      }
    });
  });

  group('resolveResumeFraction', () {
    test('uses an offset that matches lastPageRead', () {
      expect(
        resolveResumeFraction(
          chapter: _chapter(),
          local: _offset(3, 0.4, 1000),
        ),
        0.4,
      );
    });

    test('drops an offset left behind when another client moved progress', () {
      expect(
        resolveResumeFraction(
          chapter: _chapter(lastPageRead: 5),
          local: _offset(3, 0.4, 1000),
          // KOReader or the web UI pushed page 5; the server copy is stale too.
        ),
        isNull,
      );
    });

    test('prefers the most recent of the local and server copies', () {
      final chapter = _chapter(remote: _offset(3, 0.7, 2000).encode());
      expect(
        resolveResumeFraction(chapter: chapter, local: _offset(3, 0.4, 1000)),
        0.7,
      );
      expect(
        resolveResumeFraction(chapter: chapter, local: _offset(3, 0.2, 3000)),
        0.2,
      );
    });

    test('ignores offsets on read chapters', () {
      expect(
        resolveResumeFraction(
          chapter: _chapter(isRead: true),
          local: _offset(3, 0.4, 1000),
        ),
        isNull,
      );
    });
  });

  test('differsFrom ignores moves under 2% of the page', () {
    final base = _offset(3, 0.40, 1000);
    expect(_offset(3, 0.41, 2000).differsFrom(base), isFalse);
    expect(_offset(3, 0.45, 2000).differsFrom(base), isTrue);
    expect(_offset(4, 0.40, 2000).differsFrom(base), isTrue);
    expect(base.differsFrom(null), isTrue);
  });

  test('store keeps entries per server and caps its size', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final a = ReaderPageOffsetStore(preferences, 'http://a');
    final b = ReaderPageOffsetStore(preferences, 'http://b');
    await a.write(1, _offset(3, 0.4, 1000));
    expect(a.read(1), _offset(3, 0.4, 1000));
    expect(b.read(1), isNull);

    for (var id = 2; id <= 205; id++) {
      await a.write(id, _offset(0, 0.5, 1000 + id));
    }
    expect(a.read(1), isNull, reason: 'oldest entry evicted');
    expect(a.read(205), isNotNull);
  });
}
