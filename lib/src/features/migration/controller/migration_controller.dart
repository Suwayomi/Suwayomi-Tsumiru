// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../browse_center/data/source_repository/source_repository.dart';
import '../../browse_center/domain/source/source_model.dart';
import '../../browse_center/presentation/source/controller/source_controller.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../../settings/presentation/general/timeout_settings/timeout_settings_section.dart';

part 'migration_controller.g.dart';

typedef MigrationQuickSearchResults = ({
  SourceDto source,
  AsyncValue<List<MangaDto>> mangaList,
});

// The row's Retry is the only re-fetch; a failed source must settle at once.
Duration? _noRetry(int retryCount, Object error) => null;

@Riverpod(retry: _noRetry)
Future<List<MangaDto>> migrationSourceQuickSearchMangaList(
  Ref ref,
  String sourceId, {
  String? query,
}) async {
  final rateLimiterQueue = ref.watch(rateLimitQueueProvider(query));
  // Capture before awaiting; ref may be disposed afterward.
  final sourceRepository = ref.watch(sourceRepositoryProvider);
  final timeout = Duration(
    milliseconds:
        ref.watch(serverRequestTimeoutProvider) ??
        DBKeys.serverRequestTimeout.initial as int,
  );
  final mangaPage = await rateLimiterQueue.add(
    () => sourceRepository
        .fetchSourceManga(
          page: 1,
          sourceId: sourceId,
          sourceType: SourceType.SEARCH,
          query: query,
        )
        .timeout(timeout),
  );
  return [...?(mangaPage?.mangas)];
}

@riverpod
AsyncValue<List<MigrationQuickSearchResults>> migrationGlobalSearchResults(
  Ref ref, {
  String? query,
}) {
  final sourcesData = ref.watch(searchableSourcesProvider);
  final sourceList = sourcesData.value ?? const <SourceDto>[];

  final List<MigrationQuickSearchResults> sourceMangaListPairList = [];
  for (SourceDto source in sourceList) {
    if (source.id.isNotBlank) {
      final mangaList = ref.watch(
        migrationSourceQuickSearchMangaListProvider(source.id, query: query),
      );
      sourceMangaListPairList.add((mangaList: mangaList, source: source));
    }
  }

  return sourcesData.copyWithData((_) => sourceMangaListPairList);
}
