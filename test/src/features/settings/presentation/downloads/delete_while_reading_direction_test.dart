// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

ChapterDto _ch(
  int id, {
  required double number,
  required int sourceOrder,
  String? scanlator,
  bool isRead = false,
  bool isDownloaded = true,
}) => Fragment$ChapterDto(
  id: id,
  mangaId: 1,
  name: 'c$number',
  chapterNumber: number,
  sourceOrder: sourceOrder,
  scanlator: scanlator,
  isRead: isRead,
  isBookmarked: false,
  isDownloaded: isDownloaded,
  lastPageRead: 0,
  pageCount: 10,
  fetchedAt: '0',
  uploadDate: '0',
  lastReadAt: '0',
  url: '',
  meta: const <Fragment$ChapterDto$meta>[],
);

class _PreferAlpha extends MangaPreferredScanlators {
  @override
  List<String> build({required int mangaId}) => const ['Alpha'];
}

class _SlowChapterList extends MangaChapterList {
  final gate = Completer<List<ChapterDto>?>();

  @override
  Future<List<ChapterDto>?> build({required int mangaId}) => gate.future;
}

void main() {
  testWidgets(
    'the delete target is the chapter 2 back in reading order, whatever the '
    'screen is showing and whichever scanlator was read',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final slow = _SlowChapterList();

      // Chapter 3 exists twice. The reader is on Bravo's copy, but Alpha is the
      // preferred group, so dedup would drop id 33 unless it is pinned.
      // Newest first, as the details screen would show it.
      final chapters = [
        _ch(4, number: 4, sourceOrder: 5, scanlator: 'Alpha'),
        _ch(3, number: 3, sourceOrder: 4, scanlator: 'Alpha'),
        _ch(
          33,
          number: 3,
          sourceOrder: 3,
          scanlator: 'Bravo',
          isRead: true,
          isDownloaded: false,
        ),
        _ch(2, number: 2, sourceOrder: 2, scanlator: 'Alpha', isRead: true),
        _ch(1, number: 1, sourceOrder: 1, scanlator: 'Alpha', isRead: true),
      ];

      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            mangaChapterListProvider(mangaId: 1).overrideWith(() => slow),
            mangaPreferredScanlatorsProvider(
              mangaId: 1,
            ).overrideWith(() => _PreferAlpha()),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      final pending = whileReadingDeleteTarget(captured, 1, 33, 2);
      slow.gate.complete(chapters);
      await tester.pump();

      expect(
        await pending,
        2,
        reason:
            'two slots back from chapter 3 is chapter 2, found even though '
            'the list arrived late and dedup prefers the other group',
      );
    },
  );
}
