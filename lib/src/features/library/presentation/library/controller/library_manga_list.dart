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
import '../../../../../features/offline/data/server_reachability.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/category_repository.dart';

part 'library_manga_list.g.dart';

@riverpod
Future<List<MangaDto>?> libraryMangaList(Ref ref) async {
  final offlineDb = ref.watch(offlineReadDatabaseProvider);
  // Captured before the await; the keepAlive notifier outlives this provider.
  final reachability = ref.read(serverUnreachableProvider.notifier);
  final list = await libraryWithOfflineFallback(
    fetch: () => ref.watch(categoryRepositoryProvider).getAllLibraryMangas(),
    // Only read the native-only DB when offline is available (never on web).
    db: offlineDb,
    offlineEnabled: offlineDb != null,
    // Riverpod forbids modifying another provider while this one is building,
    // so defer the flip to a later tick (past the build) and ignore it if the
    // container is already gone.
    onReachability: (reachable) => Future(() {
      try {
        reachability.set(!reachable);
      } catch (_) {}
    }),
  );
  final sync = ref.read(offlineSyncProvider);
  if (sync != null && list != null) {
    for (final manga in list) {
      unawaited(sync.syncManga(manga));
    }
  }
  return list;
}
