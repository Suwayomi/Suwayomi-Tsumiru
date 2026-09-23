// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Selecting a library and pressing Download to server used to queue every
// chapter of every series, so a 85-series selection put over 13,000 entries in
// the server's queue when only a few hundred were actually missing.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/presentation/library/category_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_download_presets.dart';

import '../manga_book/manga_details/chapter_test_helpers.dart';

void main() {
  group('serverDownloadIds', () {
    test('skips chapters the server already holds', () {
      final ids = serverDownloadIds([
        ch(id: 1, number: 1, isDownloaded: true),
        ch(id: 2, number: 2),
        ch(id: 3, number: 3, isDownloaded: true),
        ch(id: 4, number: 4),
      ]);
      expect(ids, [2, 4]);
    });

    test('a fully downloaded series queues nothing', () {
      final ids = serverDownloadIds([
        ch(id: 1, number: 1, isDownloaded: true),
        ch(id: 2, number: 2, isDownloaded: true),
      ]);
      expect(ids, isEmpty);
    });

    for (final entry in {
      DownloadPreset.nextChapter: 1,
      DownloadPreset.next5: 5,
      DownloadPreset.next10: 10,
      DownloadPreset.next25: 25,
    }.entries) {
      test('${entry.key} applies independently to each series', () {
        for (final offset in [0, 100]) {
          final chapters = [
            for (var number = 30; number >= 1; number--)
              ch(
                id: offset + number,
                number: number.toDouble(),
                isRead: number == 3,
                isDownloaded: number == 5,
              ),
          ];
          expect(
            serverDownloadIds(chapters, preset: entry.key),
            [
              for (var n = 4; n <= 30; n++)
                if (n != 5) offset + n,
            ].take(entry.value).toList(),
          );
        }
      });
    }

    test('unread includes gaps before the reading position', () {
      expect(
        serverDownloadIds([
          ch(id: 1, number: 1),
          ch(id: 2, number: 2, isRead: true),
          ch(id: 3, number: 3, isDownloaded: true),
          ch(id: 4, number: 4),
        ], preset: DownloadPreset.unread),
        [1, 4],
      );
    });

    test('all includes read chapters in reading order', () {
      expect(
        serverDownloadIds([
          ch(id: 3, number: 3),
          ch(id: 1, number: 1, isRead: true),
          ch(id: 2, number: 2, isDownloaded: true),
        ], preset: DownloadPreset.all),
        [1, 3],
      );
    });

    test('every preset handles absent and downloaded chapters', () {
      for (final preset in DownloadPreset.values) {
        expect(serverDownloadIds(null, preset: preset), isEmpty);
        expect(serverDownloadIds([], preset: preset), isEmpty);
        expect(
          serverDownloadIds([
            ch(id: 1, number: 1, isDownloaded: true),
          ], preset: preset),
          isEmpty,
        );
      }
    });

    test('a null chapter list queues nothing', () {
      expect(serverDownloadIds(null), isEmpty);
    });
  });
}
