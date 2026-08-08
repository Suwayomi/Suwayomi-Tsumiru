// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// A chapter waiting in the server's download queue used to render the same
// indeterminate spinner as one actually downloading. Spinners repaint every
// frame, so queueing a series set every visible row animating for as long as
// the queue lasted, whether or not anything was being fetched.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/widgets/download_status_icon.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/widgets/custom_circular_progress_indicator.dart';

DownloadDto _download(DownloadState state, double progress) =>
    Fragment$DownloadDto(
      chapter: Fragment$DownloadDto$chapter(
        id: 1,
        name: 'c1',
        sourceOrder: 1,
        isDownloaded: false,
      ),
      manga: Fragment$DownloadDto$manga(id: 1, title: 'M', downloadCount: 0),
      progress: progress,
      state: state,
      tries: 0,
      position: 0,
    );

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
  Future<void> pump(WidgetTester tester, DownloadDto? download) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offlineEnabledProvider.overrideWithValue(false),
          downloadsFromIdProvider(1).overrideWithValue(download),
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
    await tester.pump();
  }

  testWidgets('a queued chapter shows a static icon, not a spinner', (
    tester,
  ) async {
    await pump(tester, _download(DownloadState.QUEUED, 0));

    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(
      find.byType(MiniCircularProgressIndicator),
      findsNothing,
      reason: 'an animating spinner here repaints every visible row per frame',
    );
  });

  testWidgets('a downloading chapter still shows progress', (tester) async {
    await pump(tester, _download(DownloadState.DOWNLOADING, 0.5));

    expect(find.byType(MiniCircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
  });
}
