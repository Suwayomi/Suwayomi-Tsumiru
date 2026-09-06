// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/widgets/download_progress_list_tile.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

DownloadDto _download({
  required DownloadState state,
  double progress = 0,
  int pageCount = 20,
  int tries = 0,
}) =>
    Fragment$DownloadDto(
      chapter: Fragment$DownloadDto$chapter(
        id: 1,
        name: 'Chapter 1',
        sourceOrder: 1,
        isDownloaded: false,
        pageCount: pageCount,
      ),
      manga: Fragment$DownloadDto$manga(
        id: 1,
        title: 'Test Manga',
        downloadCount: 0,
      ),
      progress: progress,
      state: state,
      tries: tries,
      position: 0,
    );

Future<void> _pump(WidgetTester tester, DownloadDto download) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadsFromIdProvider(1).overrideWithValue(download),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DownloadProgressListTile(
            chapterId: 1,
            toast: null,
            index: 0,
            downloadsCount: 1,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('queued row shows the queued label, no progress bar, no retry',
      (tester) async {
    await _pump(tester, _download(state: DownloadState.QUEUED));

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DownloadProgressListTile)))!;
    expect(find.text(l10n.queued), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.retry), findsNothing);
    expect(find.text(l10n.cancel), findsOneWidget);
  });

  testWidgets('downloading row shows page progress and a progress bar',
      (tester) async {
    await _pump(
      tester,
      _download(state: DownloadState.DOWNLOADING, progress: 0.96, pageCount: 25),
    );

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DownloadProgressListTile)))!;
    expect(find.textContaining('24/25'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.retry), findsNothing);
  });

  testWidgets('error row shows the error label, no progress bar, and retry',
      (tester) async {
    await _pump(
      tester,
      _download(state: DownloadState.ERROR, tries: 3),
    );

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DownloadProgressListTile)))!;
    expect(find.textContaining('Error'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.retry), findsOneWidget);
  });
}
