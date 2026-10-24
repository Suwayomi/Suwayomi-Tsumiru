// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/legacy.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../constants/enum.dart';
import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import '../../../data/source_repository/source_repository.dart';
import '../../../domain/source/source_model.dart';
import '../../source/controller/source_controller.dart';

part 'source_quick_search_controller.g.dart';

/// Global server meta storing the scope enum name ("pinned" or "all").
const kGlobalSearchScopeMetaKey = 'tsumiru_global_search_scope';

/// Uses local prefs offline and syncs scope through server meta.
@riverpod
class GlobalSearchScope extends _$GlobalSearchScope
    with SharedPreferenceEnumClientMixin<GlobalSearchSourceFilter> {
  @override
  GlobalSearchSourceFilter? build() {
    final local = initialize(
      DBKeys.globalSearchSourceFilter,
      enumList: GlobalSearchSourceFilter.values,
    );
    _adoptServerValue();
    return local;
  }

  Future<void> _adoptServerValue() async {
    try {
      final before = state;
      final metas = await ref
          .read(deleteChaptersSettingsRepositoryProvider)
          .getGlobalMetas();
      String? raw;
      for (final m in metas ?? const []) {
        if (m.key == kGlobalSearchScopeMetaKey) raw = m.value;
      }
      final server = GlobalSearchSourceFilter.values
          .where((e) => e.name == raw)
          .firstOrNull;
      // Only adopt if the user didn't change the scope while we were fetching.
      if (server != null && server != state && state == before) {
        super.update(server);
      }
    } catch (_) {
    }
  }

  @override
  void update(GlobalSearchSourceFilter? value) {
    super.update(value);
    if (value == null) return;
    ref
        .read(deleteChaptersSettingsRepositoryProvider)
        .setRawGlobalMeta(kGlobalSearchScopeMetaKey, value.name)
        .catchError((_) {});
  }
}

final globalSearchOnlyHasResultsProvider = StateProvider<bool>((Ref ref) => false);

typedef QuickSearchResults = ({
  SourceDto source,
  AsyncValue<List<MangaDto>> mangaList
});

// The row's Retry is the only re-fetch; a failed source must settle at once.
Duration? _noRetry(int retryCount, Object error) => null;

@Riverpod(retry: _noRetry)
Future<List<MangaDto>> sourceQuickSearchMangaList(
  Ref ref,
  String sourceId, {
  String? query,
}) async {
  final rateLimiterQueue = ref.watch(rateLimitQueueProvider(query));
  // Capture before awaiting; ref may be disposed afterward.
  final sourceRepository = ref.watch(sourceRepositoryProvider);
  final mangaPage = await rateLimiterQueue
      .add(() => sourceRepository.fetchSourceManga(
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
  // Grouped sources exclude pins; searchableSources includes them first.
  final sourcesData = ref.watch(searchableSourcesProvider);
  final scope = ref.watch(globalSearchScopeProvider);
  final pinned = ref.watch(pinnedSourcesProvider);
  final allSources = sourcesData.value ?? const <SourceDto>[];
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
