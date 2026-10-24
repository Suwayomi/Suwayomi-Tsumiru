// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../features/offline/data/offline_cover_warmer.dart';
import '../../../../../features/offline/data/offline_read_fallback.dart';
import '../../../../../features/offline/data/offline_repository.dart';
import '../../../../../features/offline/data/server_reachability.dart';
import '../../../../../utils/crash/diagnostics.dart';
import '../../../../../utils/crash/redact_tokens.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/manga_cover/providers/manga_cover_providers.dart';
import '../../../../auth/data/auth_credentials_store.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/category_repository.dart';

part 'library_manga_list.g.dart';

@riverpod
Future<List<MangaDto>?> libraryMangaList(Ref ref) async {
  final sessionCurrent = watchAuthSession(ref);
  bool current() => ref.mounted && sessionCurrent();
  if (!current()) return null;
  final offlineDb = ref.watch(offlineReadDatabaseProvider);
  final categoryRepository = ref.watch(categoryRepositoryProvider);
  // Only the optional continue-reading button needs the costly first-unread query.
  final withFirstUnread = ref
      .watch(showContinueReadingButtonProvider)
      .ifNull(false);
  // Capture dependencies before awaiting; this provider may be disposed during the fetch.
  final reachability = ref.read(serverUnreachableProvider.notifier);
  final sync = ref.read(offlineSyncProvider);
  final coverWarmer = ref.read(offlineCoverWarmerProvider.notifier);
  // Capture generation before fetching to order this response against progress push acknowledgements.
  final fetchGen = sync?.syncGeneration ?? 0;
  // Never mirror catalog echoes: that reapplies unread corrections and loses timestamp/chapter details.
  var fromServer = false;
  final offlineFirst =
      ref.watch(viewOfflineNowProvider) || ref.watch(serverUnreachableProvider);
  final List<MangaDto>? list;
  try {
    list = await libraryWithOfflineFallback(
      fetch: () async {
        final r = await categoryRepository.getAllLibraryMangas(
          withFirstUnread: withFirstUnread,
        );
        fromServer = true;
        return r;
      },
      db: offlineDb,
      offlineEnabled: offlineDb != null,
      offlineFirst: offlineFirst,
      // Defer reachability changes until after build; Riverpod forbids provider writes during build.
      onReachability: (reachable) {
        Future(() {
          try {
            if (current()) {
              reachability.set(!reachable, reason: 'library-fetch');
            }
          } catch (_) {}
        });
      },
    );
  } catch (e) {
    // Connection errors bypass the provider-failure log.
    recordDiagnostic(
      redactTokens(
        '[${DateTime.now().toIso8601String()}] library-list: failed '
        'offlineFirst=$offlineFirst error=${e.runtimeType}: $e\n',
      ),
    );
    rethrow;
  }
  if (!current()) return null;
  recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] library-list: '
    'source=${fromServer ? 'server' : 'catalog'} manga=${list?.length} '
    'offlineFirst=$offlineFirst\n',
  );
  if (list != null && fromServer) {
    if (sync != null) {
      for (final manga in list) {
        unawaited(sync.syncManga(manga, fetchedAtGen: fetchGen));
      }
      unawaited(sync.pruneRemovedLibraryManga(list));
    }
    // Warm covers even for unopened series so they remain available offline.
    unawaited(coverWarmer.warmLibraryCovers(list));
  }
  return list;
}
