// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_session_storage.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery.dart';
import 'package:tsumiru/src/features/offline/data/account_storage_recovery_state.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_stall.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_series_entry.dart';
import 'package:tsumiru/src/features/offline/presentation/account_storage_recovery_banner.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_files_view.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../helpers/offline_test_db.dart';

class _RecordingRecovery extends AccountSessionStorage {
  _RecordingRecovery(super.ref, this.saved);
  final List<Map<int, bool>> saved;
  @override
  Future<void> recover({Map<int, bool> progressChoices = const {}}) async {
    saved.add(Map.of(progressChoices));
  }
}

void main() {
  testWidgets(
    'progress conflict requires a choice and retries with that choice',
    (tester) async {
      final saved = <Map<int, bool>>[];
      final container = ProviderContainer(
        overrides: [
          accountSessionStorageProvider.overrideWith(
            (ref) => _RecordingRecovery(ref, saved),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(accountStorageRecoveryProvider.notifier)
          .update(
            const AccountStorageRecoveryState(
              AccountStorageRecoveryPhase.failed,
              conflicts: [
                AccountProgressConflict(
                  chapterId: 7,
                  name: 'Chapter 7',
                  originalPage: 112,
                  currentPage: 0,
                  originalRead: true,
                  currentRead: false,
                  originalBookmarked: false,
                  currentBookmarked: true,
                  originalLastReadAt: '1700000000',
                  originalPendingFields: ['progress_dirty', 'read_state_dirty'],
                  originalReadStateManual: true,
                ),
              ],
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: AccountStorageRecoveryBanner()),
          ),
        ),
      );
      await tester.tap(find.text('Review progress'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'Save');
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      expect(find.textContaining('Page: 113'), findsOneWidget);
      expect(find.textContaining('Last read: Not recorded'), findsOneWidget);
      expect(find.textContaining('2023'), findsOneWidget);
      expect(
        find.textContaining('Pending sync: page position, read status'),
        findsOneWidget,
      );
      expect(find.textContaining('No pending changes'), findsOneWidget);
      expect(
        find.textContaining('Read status changed manually'),
        findsOneWidget,
      );
      expect(find.textContaining('Page: 1 · Unread'), findsOneWidget);
      await tester.tap(find.text('Use current'));
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, [
        {7: false},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recovery explains unavailable downloads instead of showing an empty collection',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          settledAccountAccessProvider.overrideWithValue(
            AccountAccess(capability: AccountCapability.unsupported),
          ),
          offlineEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(accountStorageRecoveryProvider.notifier)
          .update(
            const AccountStorageRecoveryState(
              AccountStorageRecoveryPhase.recovering,
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  AccountStorageRecoveryBanner(),
                  Expanded(child: OfflineFilesView()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Recovering downloads'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      container
          .read(accountStorageRecoveryProvider.notifier)
          .update(
            const AccountStorageRecoveryState(
              AccountStorageRecoveryPhase.failed,
            ),
          );
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  for (final counts in [
    (downloaded: 0, inFlight: 0),
    (downloaded: 2, inFlight: 0),
    (downloaded: 0, inFlight: 1),
  ]) {
    final downloaded = counts.downloaded;
    testWidgets('shows failed count with $counts', (tester) async {
      final db = testOfflineDatabase();
      addTearDown(db.close);
      await db.upsertMangaMetadata(
        id: 1,
        title: 'Manual series',
        updatedAt: DateTime(2026),
      );
      final manga = await db.mangaById(1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settledAccountAccessProvider.overrideWithValue(
              AccountAccess(capability: AccountCapability.unsupported),
            ),
            offlineEnabledProvider.overrideWithValue(true),
            offlineSeriesProvider.overrideWith(
              (ref) => Stream.value([
                OfflineSeriesEntry(
                  manga: manga!,
                  downloaded: downloaded,
                  inFlight: counts.inFlight,
                  bytes: 0,
                  failed: 1,
                ),
              ]),
            ),
            offlineUsageBytesProvider.overrideWith((ref) async => 0),
            effectiveDownloadStallProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: OfflineFilesView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manual series'), findsOneWidget);
      expect(find.textContaining('Failed: 1'), findsOneWidget);
      final context = tester.element(find.byType(OfflineFilesView));
      final l10n = AppLocalizations.of(context)!;
      expect(find.text(l10n.manageDownloadsNothingYet), findsNothing);
      if (downloaded > 0) {
        expect(find.textContaining(l10n.nChapters(downloaded)), findsOneWidget);
      }
      if (counts.inFlight > 0) {
        expect(
          find.textContaining(l10n.offlineDownloadingCount(counts.inFlight)),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
