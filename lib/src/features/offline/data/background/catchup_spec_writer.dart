// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../constants/db_keys.dart';
import '../../../../global_providers/global_providers.dart';
import '../../../../utils/logger/logger.dart';
import '../offline_database.dart';
import '../offline_download_providers.dart';
import '../offline_repository.dart';
import '../offline_settings_providers.dart';
import '../offline_types.dart';
import 'catchup_work_spec.dart';

/// Provider-read indirection so the writer runs off the root container or a
/// WidgetRef alike.
typedef CatchupRead = T Function<T>(ProviderListenable<T> provider);

/// Snapshot the background download step's world from drift + settings.
/// Called after catch-up/reconcile passes, on keep-rule changes, and on app
/// pause — the worker reads the newest snapshot it can get, never drift.
Future<void> writeCatchupWorkSpec(CatchupRead read) async {
  try {
    // offlineActiveProvider depends on serverInstanceIdProvider (.value), an
    // async FutureProvider that may be null at pause/hide time (the provider
    // is auto-dispose and restarts asynchronously). Guard only on the sync
    // flag; the serverId null-check below already rejects a no-catalog state.
    if (!read(offlineEnabledProvider)) return;
    final serverId = read(
      sharedPreferencesProvider,
    ).getString(DBKeys.offlineCatalogServerId.name);
    if (serverId == null) return;

    final db = read(offlineDatabaseProvider);
    final nets = read(safetyNetConfigProvider);
    final specs = <CatchupMangaSpec>[];
    var usedBytes = 0;
    for (final m in await db.libraryManga()) {
      final all = await db.chaptersForManga(m.id);
      for (final c in all) {
        if (c.deviceState == OfflineDeviceState.downloaded)
          usedBytes += c.bytes;
      }
      if (m.keepRule == OfflineKeepRule.off) continue;
      final chapters = all;
      specs.add(
        CatchupMangaSpec(
          mangaId: m.id,
          keepRule: m.keepRule,
          keepUnreadCount: m.keepUnreadCount,
          onDeviceChapterIds: {
            for (final c in chapters)
              if (c.deviceState == OfflineDeviceState.downloaded) c.id,
          },
          pinnedChapterIds: {
            for (final c in chapters)
              if (c.pinned) c.id,
          },
          // Only the deleted-at-least-once chapters; everything else is 0.
          chapterGenerations: {
            for (final c in chapters)
              if (c.downloadGeneration != 0) c.id: c.downloadGeneration,
          },
        ),
      );
    }

    final store = CatchupStateStore(read(sharedPreferencesProvider));
    await store.writeSpec(
      CatchupWorkSpec(
        serverId: serverId,
        wifiOnly: read(offlineWifiOnlyProvider) ?? true,
        storageCapEnabled: nets.storageCapEnabled,
        storageCapBytes: nets.storageCapBytes,
        usedBytes: usedBytes,
        manga: specs,
      ),
    );
  } catch (e) {
    // A stale spec beats a crashed caller — the worker treats staleness as
    // normal and the next foreground pass rewrites it.
    logger.w('Offline: writing the catch-up work spec failed: $e');
  }
}
