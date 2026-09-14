import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/domain/account_access.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_stall.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_series_entry.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_files_view.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import '../../../../helpers/offline_test_db.dart';

void main() {
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
