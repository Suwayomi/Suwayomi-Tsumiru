// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../features/offline/data/offline_read_fallback.dart';
import '../../../../../features/offline/data/offline_repository.dart';
import '../../../../../features/offline/data/offline_settings_providers.dart';
import '../../../../../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../../../../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/category_repository.dart';

part 'library_manga_list.g.dart';

@riverpod
Future<List<MangaDto>?> libraryMangaList(Ref ref) async {
  final offlineEnabled = ref.watch(offlineEnabledProvider);
  // Suppress the offline fallback when the catalog came from a different server,
  // so a switch can't show the old server's downloads (#145). A null origin
  // (cold start / pre-existing install) is trusted.
  final currentServer =
      '${ref.watch(serverUrlProvider)}|${ref.watch(serverPortProvider)}';
  final catalogServer = ref.read(offlineCatalogServerUrlProvider);
  final canUseOffline = offlineEnabled &&
      (catalogServer == null || catalogServer == currentServer);

  final list = await libraryWithOfflineFallback(
    fetch: () => ref.watch(categoryRepositoryProvider).getAllLibraryMangas(),
    db: canUseOffline ? ref.watch(offlineDatabaseProvider) : null,
    offlineEnabled: canUseOffline,
  );
  if (list != null) {
    // Record which server the catalog now reflects.
    ref.read(offlineCatalogServerUrlProvider.notifier).update(currentServer);
    final sync = ref.read(offlineSyncProvider);
    if (sync != null) {
      for (final manga in list) {
        unawaited(sync.syncManga(manga));
      }
    }
  }
  return list;
}
