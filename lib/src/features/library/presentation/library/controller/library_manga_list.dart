// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../features/offline/data/offline_cover_warmer.dart';
import '../../../../../features/offline/data/offline_read_fallback.dart';
import '../../../../../features/offline/data/offline_repository.dart';
import '../../../../../features/offline/data/server_reachability.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/category_repository.dart';

part 'library_manga_list.g.dart';

@riverpod
Future<List<MangaDto>?> libraryMangaList(Ref ref) async {
  final offlineDb = ref.watch(offlineReadDatabaseProvider);
  final categoryRepository = ref.watch(categoryRepositoryProvider);
  // Captured before the await; touching ref after the async gap throws if this
  // provider was disposed mid-build. The keepAlive notifiers outlive it.
  final reachability = ref.read(serverUnreachableProvider.notifier);
  final sync = ref.read(offlineSyncProvider);
  final coverWarmer = ref.read(offlineCoverWarmerProvider.notifier);
  // Ordered against push acks: captured before the fetch goes out.
  final fetchGen = sync?.syncGeneration ?? 0;
  // Mirror only genuine server responses. Fallback DTOs are catalog echoes:
  // they already carry the unread correction (double-applied if written
  // back), and the DTO round-trip loses lastReadAt and real chapter numbers.
  var fromServer = false;
  // Kept for the reachability flip below; fromServer is the mirror gate.
  var serverReachable = true;
  final list = await libraryWithOfflineFallback(
    fetch: () async {
      final r = await categoryRepository.getAllLibraryMangas();
      fromServer = true;
      return r;
    },
    // Only read the native-only DB when offline is available (never on web).
    db: offlineDb,
    offlineEnabled: offlineDb != null,
    offlineFirst:
        ref.watch(viewOfflineNowProvider) ||
        ref.watch(serverUnreachableProvider),
    // Riverpod forbids modifying another provider while this one is building,
    // so defer the flip to a later tick (past the build) and ignore it if the
    // container is already gone.
    onReachability: (reachable) {
      serverReachable = reachable;
      Future(() {
        try {
          reachability.set(!reachable);
        } catch (_) {}
      });
    },
  );
  if (list != null && fromServer) {
    if (sync != null) {
      for (final manga in list) {
        unawaited(sync.syncManga(manga, fetchedAtGen: fetchGen));
      }
      unawaited(sync.pruneRemovedLibraryManga(list));
    }
    // Top up missing library covers in the durable cover cache, so a series
    // never opened still has its cover when the server is unreachable.
    unawaited(coverWarmer.warmLibraryCovers(list));
  }
  return list;
}
