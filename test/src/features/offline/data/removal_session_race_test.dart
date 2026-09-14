import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller_shim.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/features/offline/presentation/offline_settings_screen.dart';
import 'package:tsumiru/src/features/offline/presentation/series_offline_button.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

class _Database extends OfflineDatabase {
  _Database(this.pauseAt) : super(NativeDatabase.memory());
  final String? pauseAt;
  final started = Completer<void>();
  final release = Completer<void>();
  int libraryReads = 0;
  int downloadedReads = 0;

  Future<void> pause(String step) async {
    if (pauseAt != step) return;
    started.complete();
    await release.future;
  }

  @override
  Future<List<OfflineManga>> libraryManga() async {
    libraryReads++;
    await pause('library');
    return super.libraryManga();
  }

  @override
  Future<List<OfflineChapter>> downloadedChaptersForManga(int mangaId) async {
    downloadedReads++;
    await pause('downloaded');
    return super.downloadedChaptersForManga(mangaId);
  }

  @override
  Future<List<OfflineChapter>> chaptersForManga(int mangaId) async {
    await pause('series');
    return super.chaptersForManga(mangaId);
  }
}

class _Background extends BackgroundDownloadController {
  _Background(super.ref);
  @override
  Future<T> withOwnership<T>(Future<T> Function() action) => action();
}

Future<void> _seed(_Database db) async {
  await db.upsertMangaMetadata(
    id: 1,
    title: 'Series',
    updatedAt: DateTime(2026),
    inLibraryAt: '1',
  );
  await db.setKeepRule(1, OfflineKeepRule.all, 10);
  await db.upsertChapterMetadata(
    id: 1,
    mangaId: 1,
    name: 'Chapter',
    chapterIndex: 1,
    isRead: false,
    lastPageRead: 0,
    isBookmarked: false,
    serverIsDownloaded: true,
    pageCount: 1,
    updatedAt: DateTime(2026),
  );
  await db.setChapterDeviceState(1, OfflineDeviceState.downloaded);
}

void main() {
  for (final pauseAt in ['series', 'library', 'downloaded', 'confirmation']) {
    testWidgets('$pauseAt removal cannot continue into another account', (
      tester,
    ) async {
      await tester.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final a = _Database(pauseAt);
        final b = _Database(null);
        await _seed(a);
        await _seed(b);
        var deleteReads = 0;
        OfflineDatabase database = a;
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            offlineEnabledProvider.overrideWithValue(true),
            offlineActiveProvider.overrideWithValue(true),
            offlineDatabaseProvider.overrideWith((ref) => database),
            offlineRepositoryProvider.overrideWith(
              (ref) => OfflineRepository(
                db: ref.watch(offlineDatabaseProvider),
                paths: const OfflinePaths('/unused'),
              ),
            ),
            offlineServerMismatchProvider.overrideWith((ref) async => null),
            offlineUsageBytesProvider.overrideWith((ref) async => 0),
            mangaKeepConfigProvider(1).overrideWith(
              (ref) async => (rule: OfflineKeepRule.all, count: 10),
            ),
            mangaOfflineProgressProvider(
              1,
            ).overrideWith((ref) => Stream.value((downloaded: 1, inFlight: 0))),
            backgroundDownloadControllerProvider.overrideWith(_Background.new),
            offlineDownloadManagerProvider.overrideWith((ref) {
              deleteReads++;
              return null;
            }),
          ],
        );
        await container.read(authCredentialsStoreProvider.future);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: pauseAt == 'series'
                  ? const Scaffold(body: SeriesOfflineButton(mangaId: 1))
                  : const OfflineSettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (pauseAt == 'series') {
          await tester.tap(find.byType(SeriesOfflineButton));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.text('Remove all downloads'));
          await tester.pumpAndSettle();
        }
        if (pauseAt == 'confirmation') {
          await container
              .read(authCredentialsStoreProvider.notifier)
              .withIdentityChange(() async {});
          database = b;
          container.invalidate(offlineDatabaseProvider);
          await tester.tap(find.widgetWithText(TextButton, 'Delete'));
          await tester.pumpAndSettle();
        } else {
          final tile = pauseAt == 'series'
              ? tester.widget<ListTile>(
                  find.widgetWithText(ListTile, 'Remove all (this series)'),
                )
              : null;
          if (tile != null) {
            tile.onTap!();
          } else {
            await tester.tap(find.widgetWithText(TextButton, 'Delete'));
          }
          await a.started.future;
          var drained = false;
          final drain = container
              .read(offlineRuntimeStorageProvider.notifier)
              .drain()
              .then((_) => drained = true);
          await Future<void>.delayed(Duration.zero);
          final wasBlocked = !drained;
          await container
              .read(authCredentialsStoreProvider.notifier)
              .withIdentityChange(() async {});
          database = b;
          container.invalidate(offlineDatabaseProvider);
          await tester.pumpWidget(const SizedBox());
          a.release.complete();
          await drain;
          await Future<void>.delayed(Duration.zero);
          expect(wasBlocked, isTrue);
        }
        expect(b.libraryReads, 0);
        expect(b.downloadedReads, 0);
        expect(deleteReads, 0);
        expect(tester.takeException(), isNull);
        expect(
          (await b.chapterById(1))!.deviceState,
          OfflineDeviceState.downloaded,
        );
        expect((await b.mangaById(1))!.keepRule, OfflineKeepRule.all);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await a.close();
        await b.close();
      });
    });
  }
}
