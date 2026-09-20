// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/downloads/downloads_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/downloads_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/downloads/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/presentation/downloads/controller/downloads_controller.dart';
import 'package:tsumiru/src/features/manga_book/widgets/download_status_icon.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/widgets/custom_circular_progress_indicator.dart';

import '../../../helpers/legacy_account_access.dart';


DownloadDto _download(DownloadState state, double progress, {int id = 1}) =>
    Fragment$DownloadDto(
      chapter: Fragment$DownloadDto$chapter(
        id: id,
        name: 'c1',
        sourceOrder: 1,
        isDownloaded: false,
        pageCount: 20,
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

class _Session extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

class _Downloads extends DownloadsRepository {
  _Downloads()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
        permissions: legacyAccountPermissions,
      );

  @override
  Future<void> addChaptersBatchToDownloadQueue(List<int> chapterIds) async {}
}

DownloadUpdatesDto _event(DownloadUpdateType type, {int id = 1}) =>
    DownloadUpdatesDto.fromJson({
      'state': 'STARTED',
      'omittedUpdates': false,
      'updates': [
        {
          'type': type.name,
          'download': _download(
            type == DownloadUpdateType.FINISHED
                ? DownloadState.FINISHED
                : DownloadState.QUEUED,
            0,
            id: id,
          ).toJson(),
          '__typename': 'DownloadUpdate',
        },
      ],
      'initial': null,
      '__typename': 'DownloadUpdates',
    });

void main() {
  Future<void> pump(WidgetTester tester, DownloadDto? download) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
          offlineEnabledProvider.overrideWithValue(false),
          downloadsFromIdProvider(1).overrideWithValue(download),
          downloadUpdatesProvider.overrideWith((ref) => const Stream.empty()),
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

  for (final immediate in [false, true]) {
    testWidgets(
      immediate
          ? 'successful enqueue refreshes an already available server chapter'
          : 'matching raw completion refreshes after the queue removes it',
      (tester) async {
        final feed = StreamController<DownloadUpdatesDto?>();
        final downloaded = ValueNotifier(false);
        var refreshes = 0;
        final container = ProviderContainer(
          overrides: [
            settledAccountAccessProvider.overrideWithValue(legacyAccountAccess),
            offlineEnabledProvider.overrideWithValue(false),
            authCredentialsStoreProvider.overrideWith(_Session.new),
            downloadUpdatesProvider.overrideWith((ref) => feed.stream),
            downloadStatusProvider.overrideWith((ref) async => null),
            downloadsRepositoryProvider.overrideWithValue(_Downloads()),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await feed.close();
          downloaded.dispose();
        });
        await container.read(authCredentialsStoreProvider.future);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: downloaded,
                  builder: (context, value, child) => DownloadStatusIcon(
                    updateData: () async {
                      refreshes++;
                      downloaded.value = true;
                    },
                    chapter: _chapter(),
                    mangaId: 1,
                    isDownloaded: value,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        if (immediate) {
          await tester.tap(find.byIcon(Icons.cloud_download_outlined));
          // The button shows a spinner until the queue feed reports the
          // chapter, capped at 10 seconds; this test never feeds it.
          await tester.pump(const Duration(seconds: 10));
        } else {
          feed.add(_event(DownloadUpdateType.QUEUED));
          await tester.pump();
          await tester.pump();
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          feed.add(_event(DownloadUpdateType.FINISHED, id: 2));
          await tester.pump();
          expect(refreshes, 0);
          feed.add(_event(DownloadUpdateType.FINISHED));
        }
        await tester.pumpAndSettle();
        expect(refreshes, 1);
        expect(container.read(downloadsMapProvider).containsKey(1), isFalse);
        expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
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
