// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/endpoints.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/logger/logger.dart';
import '../../../utils/platform/is_android_native.dart';
import '../../auth/data/auth_coordinator.dart';
import '../../manga_book/data/manga_book/manga_book_repository.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'chapter_download_engine.dart';
import 'offline_database.dart';
import 'offline_download_coordinator.dart';
import 'offline_download_providers.dart';
import 'offline_repository.dart';
import 'offline_settings_providers.dart';

part 'offline_background_downloads.g.dart';

/// The chapter download engine wired with real deps: an auth'd HTTP page fetch
/// (resolving the server base + current auth at request time), the on-disk page
/// store, and a token refresher. Pure Dart — runs the same on Android and the
/// Linux desktop build. Null on web / when offline storage is unavailable.
@riverpod
ChapterDownloadEngine? chapterDownloadEngine(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return null;
  // Page-level parallelism (Komikku's parallelPageLimit). One chapter downloads
  // at a time; this is how many of its pages are in flight at once.
  final parallel = (ref.watch(offlineDownloadConcurrencyProvider) ??
          DBKeys.offlineDownloadConcurrency.initial as int)
      .clamp(1, 10);
  return ChapterDownloadEngine(
    fetchPage: (pageUrl) => fetchOfflinePageBytes(ref, pageUrl),
    writePage: ref.watch(offlinePageStoreProvider),
    parallelPageLimit: parallel,
    refreshAuth: () async {
      // Only ui_login has a refreshable rotating token. basic / simple_login /
      // none don't rotate, so a 401 there means the credential is wrong — no
      // point retrying.
      if (ref.read(authTypeKeyProvider) != AuthType.uiLogin) return false;
      // Refresh through a raw client (not the auth-linked one) so the refresh
      // mutation itself can't recurse through SuwayomiAuthLink; the coordinator
      // owns single-flight dedup, so concurrent 401s collapse to one refresh.
      final rawClient = GraphQLClient(
        link: HttpLink(Endpoints.baseApi(
          baseUrl: ref.read(serverUrlProvider) ?? DBKeys.serverUrl.initial,
          port: ref.read(serverPortProvider),
          addPort: ref.read(serverPortToggleProvider).ifNull(),
          isGraphQl: true,
        )),
        cache: GraphQLCache(),
      );
      final outcome = await ref
          .read(authCoordinatorProvider.notifier)
          .refreshUiAccessToken(gqlClient: rawClient);
      return outcome is RefreshSuccess;
    },
  );
}

/// The offline download orchestrator (Komikku-style: one chapter at a time,
/// page-parallel inside the engine, run-time auth). Null on web / when offline
/// storage is unavailable.
@riverpod
OfflineDownloadCoordinator? offlineDownloadCoordinator(Ref ref) {
  if (!ref.watch(offlineEnabledProvider)) return null;
  final engine = ref.watch(chapterDownloadEngineProvider);
  if (engine == null) return null;
  final repo = ref.watch(mangaBookRepositoryProvider);
  final store = ref.watch(offlinePageStoreProvider);
  return OfflineDownloadCoordinator(
    db: ref.watch(offlineDatabaseProvider),
    engine: engine,
    resolvePages: (chapterId) async =>
        (await repo.getChapterPages(chapterId: chapterId))?.pages ??
        const <String>[],
    measureChapterBytes: store.chapterBytes,
  );
}

/// Resume offline downloads at launch. Chapters left `downloading` by a previous
/// run (the in-memory loop doesn't survive a process death) are stranded; the
/// pump resumes them one at a time, re-fetching only pages not already on disk.
/// Chapters previously marked `error` get one fresh attempt — most past errors
/// were the stale-token 401s the run-time-auth engine now avoids.
Future<void> initOfflineDownloads(ProviderContainer container) async {
  if (!container.read(offlineEnabledProvider)) return;
  // On Android the foreground-service worker owns downloads (see the corruption
  // gate in pumpDownloads + BackgroundDownloadController); the launch path calls
  // the controller instead.
  if (isAndroidNative) return;
  final coord = container.read(offlineDownloadCoordinatorProvider);
  if (coord == null) return;
  final db = container.read(offlineDatabaseProvider);
  final errored = await db.chaptersInState(OfflineDeviceState.error);
  for (final c in errored) {
    await db.setChapterDeviceState(c.id, OfflineDeviceState.queued);
  }
  if (errored.isNotEmpty) {
    logger.i('Offline: requeued ${errored.length} previously-errored chapters');
  }
  await coord.pumpDownloads();
}
