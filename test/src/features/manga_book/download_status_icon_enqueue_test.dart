// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/widgets/download_status_icon.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/widgets/custom_circular_progress_indicator.dart';

class _FakeRepo implements DownloadsRepository {
  final enqueue = Completer<void>();

  @override
  Future<void> addChaptersBatchToDownloadQueue(List<int> chapterIds) =>
      enqueue.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChapterDto _chapter() => Fragment$ChapterDto(
  id: 1,
  mangaId: 1,
  name: 'c1',
  chapterNumber: 1,
  sourceOrder: 1,
  isRead: false,
  isBookmarked: false,
  isDownloaded: false,
  lastPageRead: 0,
  pageCount: 20,
  fetchedAt: '0',
  uploadDate: '0',
  lastReadAt: '0',
  url: '',
  meta: const <Fragment$ChapterDto$meta>[],
);

void main() {
  Future<_FakeRepo> pump(WidgetTester tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offlineEnabledProvider.overrideWithValue(false),
          downloadsFromIdProvider(1).overrideWithValue(null),
          downloadsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DownloadStatusIcon(
              updateData: () async {},
              chapter: _chapter(),
              mangaId: 1,
              isDownloaded: false,
            ),
          ),
        ),
      ),
    );
    return repo;
  }

  testWidgets('tapping download shows progress before the queue reports it', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pump();

    expect(find.byType(MiniCircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);
  });

  testWidgets('a failed request puts the download button back', (
    tester,
  ) async {
    final repo = await pump(tester);

    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pump();
    repo.enqueue.completeError(Exception('offline'));
    await tester.pump();

    expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
  });

  testWidgets('progress clears if the queue never reports the chapter', (
    tester,
  ) async {
    final repo = await pump(tester);

    await tester.tap(find.byIcon(Icons.cloud_download_outlined));
    await tester.pump();
    repo.enqueue.complete();
    await tester.pump(const Duration(seconds: 11));

    expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
  });
}
