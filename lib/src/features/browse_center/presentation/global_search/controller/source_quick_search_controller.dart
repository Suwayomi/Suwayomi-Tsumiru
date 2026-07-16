// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:hooks_riverpod/legacy.dart';

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

/// Tsumiru-only server global-meta key so the scope follows the user across
/// devices. Stores the enum name ('pinned' / 'all').
const kGlobalSearchScopeMetaKey = 'tsumiru_global_search_scope';

/// Search scope for global search, remembered across launches. Local prefs
/// answer instantly (and offline); the server's global meta is the shared
/// copy — adopted on open when reachable, pushed on every change.
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
      // Offline or unreachable: the local value stands.
    }
  }

  @override
  void update(GlobalSearchSourceFilter? value) {
    super.update(value);
    if (value == null) return;
    // Best-effort cross-device sync; local prefs stay authoritative offline.
    ref
        .read(deleteChaptersSettingsRepositoryProvider)
        .setGlobalMeta(kGlobalSearchScopeMetaKey, value.name)
        .catchError((_) {});
  }
}

/// When true, only sources that returned results are shown (hide empty/loading).
final globalSearchOnlyHasResultsProvider = StateProvider<bool>((Ref ref) => false);

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
