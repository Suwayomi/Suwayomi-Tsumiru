// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/graphql/__generated__/account.graphql.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads_queue/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/widgets/download_progress_list_tile.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/widgets/server_downloads_body.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../../helpers/legacy_account_access.dart';

DownloadDto _download({
  required DownloadState state,
  int chapterId = 1,
  int mangaId = 1,
  String mangaTitle = 'Test Manga',
  bool inLibrary = true,
  String? sourceId,
  double progress = 0,
  int pageCount = 20,
  int tries = 0,
}) => Fragment$DownloadDto(
  chapter: Fragment$DownloadDto$chapter(
    id: chapterId,
    name: 'Chapter $chapterId',
    sourceOrder: 1,
    pageCount: pageCount,
    user: Fragment$DownloadDto$chapter$user(isDownloaded: false),
  ),
  manga: Fragment$DownloadDto$manga(
    id: mangaId,
    title: mangaTitle,
    user: Fragment$DownloadDto$manga$user(
      downloadCount: 0,
      inLibrary: inLibrary,
    ),
    source: sourceId == null
        ? null
        : Fragment$DownloadDto$manga$source(id: sourceId),
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
        settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
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
  testWidgets('each row state renders its label, progress and menu action', (
    tester,
  ) async {
    AppLocalizations l10nFor() => AppLocalizations.of(
      tester.element(find.byType(DownloadProgressListTile)),
    )!;

    await _pump(tester, _download(state: DownloadState.QUEUED));
    var l10n = l10nFor();
    expect(find.text(l10n.queued), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.retry), findsNothing);
    expect(find.text(l10n.cancel), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pump(
      tester,
      _download(
        state: DownloadState.DOWNLOADING,
        progress: 0.96,
        pageCount: 25,
      ),
    );
    l10n = l10nFor();
    expect(find.textContaining('24/25'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.retry), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _download(state: DownloadState.ERROR, tries: 3));
    l10n = l10nFor();
    expect(find.text(l10n.sourceRemoved), findsOneWidget);
    expect(find.textContaining('Error'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.retry), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pump(
      tester,
      _download(state: DownloadState.ERROR, tries: 3, sourceId: '1'),
    );
    l10n = l10nFor();
    expect(find.textContaining('Error'), findsOneWidget);
    expect(find.text(l10n.sourceRemoved), findsNothing);
  });

  group('only my downloads', () {
    Future<void> pumpBody(
      WidgetTester tester,
      AccountAccess access,
    ) async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settledAccountAccessProvider.overrideWithValue(access),
            sharedPreferencesProvider.overrideWithValue(prefs),
            downloadsFromIdProvider(1).overrideWithValue(
              _download(
                state: DownloadState.QUEUED,
                chapterId: 1,
                mangaId: 10,
                mangaTitle: 'Mine Manga',
              ),
            ),
            downloadsFromIdProvider(2).overrideWithValue(
              _download(
                state: DownloadState.QUEUED,
                chapterId: 2,
                mangaId: 20,
                mangaTitle: 'Foreign Manga',
                inLibrary: false,
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ServerDownloadsBody(
                downloadsChapterIds: const [1, 2],
                queueStatus: AsyncValue.data(
                  Fragment$DownloadStatusDto(
                    state: DownloaderState.STOPPED,
                    queue: const [],
                  ),
                ),
                toast: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    AppLocalizations l10nOf(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(ServerDownloadsBody)))!;

    testWidgets('managers see the toggle and foreign items stay grouped', (
      tester,
    ) async {
      await pumpBody(tester, legacyAccountAccess);
      final l10n = l10nOf(tester);

      expect(find.text('Mine Manga'), findsOneWidget);
      expect(find.text('Foreign Manga'), findsNothing);
      expect(find.text('${l10n.notInYourLibrary} (1)'), findsOneWidget);
      expect(find.text(l10n.onlyMyDownloads), findsOneWidget);

      await tester.tap(find.text('${l10n.notInYourLibrary} (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Foreign Manga'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.cancel), findsOneWidget);
      expect(find.text(l10n.cancelAllForThisSeries), findsOneWidget);
    });

    testWidgets('non-admins get the filtered view without a toggle', (
      tester,
    ) async {
      await pumpBody(
        tester,
        AccountAccess(
          capability: AccountCapability.supported,
          user: Fragment$AccountDto(
            id: 2,
            username: 'reader',
            permissions: const [],
            roles: const [Enum$UserRole.USER],
          ),
        ),
      );
      final l10n = l10nOf(tester);

      expect(find.text(l10n.onlyMyDownloads), findsNothing);
      expect(find.text('Mine Manga'), findsOneWidget);
      expect(find.text('Foreign Manga'), findsNothing);
      expect(find.textContaining(l10n.notInYourLibrary), findsNothing);
    });
  });
}
