// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/endpoints.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../account/data/account_permission.dart';
import '../../auth/data/auth_coordinator.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/custom_headers_store.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../settings/presentation/general/timeout_settings/timeout_settings_section.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'chapter_commit.dart';
import 'chapter_download_engine.dart';
import 'offline_download_coordinator.dart';
import 'offline_download_permission.dart';
import 'offline_download_progress.dart';
import 'offline_download_providers.dart';
import 'offline_repository.dart';
import 'offline_settings_providers.dart';
import 'server_reachability.dart';

part 'offline_background_downloads.g.dart';

// Keep alive: fire-and-forget downloads read runtime auth across async gaps without any watchers.
@Riverpod(keepAlive: true)
ChapterDownloadEngine? chapterDownloadEngine(Ref ref) {
  if (!ref.watch(offlineServerAccessProvider)) return null;
  final isCurrentSession = watchAuthSession(ref);
  final parallel =
      (ref.watch(offlineDownloadConcurrencyProvider) ??
              DBKeys.offlineDownloadConcurrency.initial as int)
          .clamp(1, 10);
  return ChapterDownloadEngine(
    fetchPage: (pageUrl) =>
        fetchOfflinePageBytes(ref, pageUrl, isCurrentSession: isCurrentSession),
    writePage: ref.watch(offlinePageStoreProvider),
    parallelPageLimit: parallel,
    refreshAuth: () async {
      if (!isCurrentSession()) return false;
      // Only ui_login credentials rotate; other 401s cannot be refreshed.
      if (ref.read(authTypeKeyProvider) != AuthType.uiLogin) return false;
      // Raw client prevents recursive auth-link refresh; the coordinator deduplicates concurrent 401s.
      final rawClient = GraphQLClient(
        link: HttpLink(
          Endpoints.baseApi(
            baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
            port: ref.read(serverPortProvider),
            addPort: ref.read(serverPortToggleProvider).ifNull(),
            isGraphQl: true,
          ),
          defaultHeaders: applyCustomHeaders(
            const {},
            ref.read(customHttpHeadersProvider).value,
          ),
        ),
        cache: GraphQLCache(),
        queryRequestTimeout: Duration(
          milliseconds:
              (ref.read(serverRequestTimeoutProvider) ??
                  DBKeys.serverRequestTimeout.initial as int) +
              2000,
        ),
      );
      final outcome = await ref
          .read(authCoordinatorProvider.notifier)
          .refreshUiAccessToken(
            gqlClient: rawClient,
            trigger: 'offline-downloads',
          );
      return isCurrentSession() && outcome is RefreshSuccess;
    },
  );
}

// Keep alive so every trigger reaches the coordinator that owns active work.
@Riverpod(keepAlive: true)
OfflineDownloadCoordinator? offlineDownloadCoordinator(Ref ref) {
  if (!ref.watch(offlineServerAccessProvider)) return null;
  final engine = ref.watch(chapterDownloadEngineProvider);
  if (engine == null) return null;
  final isCurrentSession = watchAuthSession(ref);
  final repo = ref.watch(mangaBookRepositoryProvider);
  final store = ref.watch(offlinePageStoreProvider);
  // Capture prefs before async pumping can outlive this provider Ref.
  final prefs = ref.watch(sharedPreferencesProvider);
  final read = ref.container.read;
  return OfflineDownloadCoordinator(
    isCurrentSession: isCurrentSession,
    db: ref.watch(offlineDatabaseProvider),
    engine: engine,
    store: store,
    resolvePages: (chapterId) async {
      if (!isCurrentSession()) {
        throw StateError('Authentication session changed');
      }
      await verifyDownloadPermission(read);
      if (!isCurrentSession()) {
        throw StateError('Authentication session changed');
      }
      final result = await repo.getChapterPages(chapterId: chapterId);
      if (result == null) throw const AccountPermissionUnavailable();
      return result.pages;
    },
    onPermissionDenied: () async {
      if (isCurrentSession()) await pauseDownloadsForPermission(read);
    },
    onProgress: (chapterId, done, total) {
      if (!isCurrentSession()) return;
      ref
          .read(offlineDownloadProgressProvider.notifier)
          .start(chapterId, total: total, done: done);
    },
    onProgressDone: (chapterId) {
      if (!isCurrentSession()) return;
      ref.read(offlineDownloadProgressProvider.notifier).clear(chapterId);
    },
    persistedPaused: () =>
        !isCurrentSession() ||
        !downloadPermissionAllowed(read) ||
        (prefs.getBool(DBKeys.offlineDownloadsPaused.name) ?? false),
    // Defer because the pump may invoke this during provider construction.
    onServerUnreachable: () => Future(() {
      if (!isCurrentSession()) return;
      try {
        ref
            .read(serverUnreachableProvider.notifier)
            .set(true, reason: 'download-pump');
      } catch (_) {}
    }),
  );
}

/// Run before launch reconciliation so it sees recovered device state; Android replay owns its recovery.
Future<void> recoverDiskAtLaunch(ProviderContainer container) async {
  if (!container.read(offlineActiveProvider)) return;
  if (isAndroidNative) return;
  await recoverChaptersOnDisk(
    db: container.read(offlineDatabaseProvider),
    store: container.read(offlinePageStoreProvider),
  );
}

/// Resumes stranded downloads; disk recovery must already have run before reconciliation.
Future<void> initOfflineDownloads(ProviderContainer container) async {
  if (!container.read(offlineActiveProvider)) return;
  if (isAndroidNative) return;
  final coord = container.read(offlineDownloadCoordinatorProvider);
  if (coord == null) return;
  // Error is terminal until an explicit user retry.
  await coord.pumpDownloads();
}
