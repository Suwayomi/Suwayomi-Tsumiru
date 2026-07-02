// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../data/source_repository/source_repository.dart';
import '../../../domain/source/source_model.dart';
import '../../source/controller/source_controller.dart';

part 'source_quick_search_controller.g.dart';

/// Global-search source scope: search only pinned sources, or
/// all of them.
enum GlobalSearchSourceFilter { pinned, all }

/// Search scope for global search. Defaults to pinned; the
/// search falls back to "all" when there are no pinned sources.
final globalSearchSourceFilterProvider =
    StateProvider<GlobalSearchSourceFilter>(
        (ref) => GlobalSearchSourceFilter.pinned);

/// When true, only sources that returned results are shown (hide empty/loading).
final globalSearchOnlyHasResultsProvider = StateProvider<bool>((ref) => false);

typedef QuickSearchResults = ({
  SourceDto source,
  AsyncValue<List<MangaDto>> mangaList
});

@riverpod
Future<List<MangaDto>> sourceQuickSearchMangaList(
  Ref ref,
  String sourceId, {
  String? query,
}) async {
  final rateLimiterQueue = ref.watch(rateLimitQueueProvider(query));
  final mangaPage = await rateLimiterQueue
      .add(() => ref.watch(sourceRepositoryProvider).fetchSourceManga(
            page: 1,
            sourceId: sourceId,
            sourceType: SourceType.SEARCH,
            query: query,
          ));
  return [...?(mangaPage?.mangas)];
}

@riverpod
AsyncValue<List<QuickSearchResults>> quickSearchResults(Ref ref,
    {String? query}) {
  // Pinned-first list of every searchable source (pinned sources are otherwise
  // excluded from the grouped map and would never be searched). The Pinned/All
  // chip narrows it to just the pinned ones; with no pinned, it's always "all".
  final sourcesData = ref.watch(searchableSourcesProvider);
  final scope = ref.watch(globalSearchSourceFilterProvider);
  final pinned = ref.watch(pinnedSourcesProvider);
  final allSources = sourcesData.valueOrNull ?? const <SourceDto>[];
  final sourceList =
      (scope == GlobalSearchSourceFilter.pinned && pinned.isNotEmpty)
          ? pinned
          : allSources;

  final List<QuickSearchResults> sourceMangaListPairList = [];
  for (SourceDto source in sourceList) {
    if (source.id.isNotBlank) {
      final mangaList = ref.watch(
        sourceQuickSearchMangaListProvider(source.id, query: query),
      );
      sourceMangaListPairList.add((mangaList: mangaList, source: source));
    }
  }

  return sourcesData.copyWithData((_) => sourceMangaListPairList);
}
