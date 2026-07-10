// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../settings/presentation/browse/widgets/show_nsfw_switch/show_nsfw_switch.dart';
import '../../../data/source_repository/source_repository.dart';
import '../../../domain/source/source_model.dart';

part 'source_controller.g.dart';

@riverpod
Future<List<SourceDto>?> sourceList(Ref ref) =>
    ref.watch(sourceRepositoryProvider).getSourceList();

/// The source list with NSFW sources removed when "Show NSFW" is off. Every
/// displayed source list derives from this (the grouped/filtered map, the
/// pinned section, global search, migration), so the toggle hides NSFW sources
/// everywhere — matching how the extensions list already behaves. Defaults to
/// showing NSFW (no filtering) when the setting is unset.
@riverpod
AsyncValue<List<SourceDto>?> visibleSourceList(Ref ref) {
  final showNsfw = ref.watch(showNSFWProvider).ifNull(true);
  return ref.watch(sourceListProvider).copyWithData(
        (list) =>
            list == null || showNsfw ? list : [...list.where((e) => !e.isNsfw)],
      );
}

int _byName(SourceDto a, SourceDto b) =>
    a.name.toLowerCase().compareTo(b.name.toLowerCase());

/// Pure: pinned sources sorted alphabetically. Pin state lives in server meta
/// (`webUI_isPinned`), so it syncs with WebUI. Exposed for testing.
List<SourceDto> pinnedSourcesFrom(List<SourceDto> sources) =>
    [...sources.where((e) => e.isPinned)]..sort(_byName);

/// Pure: group NON-pinned sources by language code (pinned live in their own
/// top section, so they're excluded here to avoid showing twice), with the
/// last-used source lifted into a "lastUsed" bucket. Every group is sorted
/// alphabetically by name. Exposed for testing.
Map<String, List<SourceDto>> groupSourcesByLanguage(
  List<SourceDto> sources,
  String? lastUsedId,
) {
  final sourceMap = <String, List<SourceDto>>{};
  for (final e in sources) {
    if (!e.isPinned) {
      sourceMap.update(
        e.language?.code ?? "other",
        (value) => [...value, e],
        ifAbsent: () => [e],
      );
    }
    if (e.id == lastUsedId) sourceMap["lastUsed"] = [e];
  }
  for (final list in sourceMap.values) {
    list.sort(_byName);
  }
  return sourceMap;
}

/// Pinned sources, surfaced as their own top section regardless of the active
/// language filter.
@riverpod
List<SourceDto> pinnedSources(Ref ref) => pinnedSourcesFrom(
    ref.watch(visibleSourceListProvider).valueOrNull ?? const []);

@riverpod
AsyncValue<Map<String, List<SourceDto>>> sourceMap(Ref ref) {
  final sourceListData = ref.watch(visibleSourceListProvider);
  final sourceLastUsed = ref.watch(sourceLastUsedProvider);
  return sourceListData.copyWithData(
    (data) => groupSourcesByLanguage(data ?? const [], sourceLastUsed),
  );
}

@riverpod
class SourceFilterLangMap extends _$SourceFilterLangMap {
  @override
  Map<String, bool> build() {
    final sourceMap = {...?ref.watch(sourceMapProvider).valueOrNull};
    final enabledLanguages = ref.watch(sourceLanguageFilterProvider);
    sourceMap.remove("lastUsed");
    sourceMap.remove("localsourcelang");
    return Map.fromIterable(
      [...sourceMap.keys],
      value: (element) => (enabledLanguages?.contains(element)).ifNull(),
    );
  }

  void toggleLang(String langCode, bool value) {
    if (!value) {
      ref.read(sourceLanguageFilterProvider.notifier).updateWithPreviousState(
          (enabledLanguages) => [...?enabledLanguages]..remove(langCode));
    } else {
      ref.read(sourceLanguageFilterProvider.notifier).updateWithPreviousState(
            (enabledLanguages) => {...?enabledLanguages, langCode}.toList(),
          );
    }
  }
}

@riverpod
AsyncValue<Map<String, List<SourceDto>>?> sourceMapFiltered(Ref ref) {
  final sourceMapFiltered = <String, List<SourceDto>>{};
  final sourceMapData = ref.watch(sourceMapProvider);
  final sourceMap = {...?sourceMapData.valueOrNull};
  final enabledLangList = [...?ref.watch(sourceLanguageFilterProvider)]..sort();
  for (final e in enabledLangList) {
    if (sourceMap.containsKey(e)) sourceMapFiltered[e] = sourceMap[e]!;
  }
  return sourceMapData.copyWithData((e) => sourceMapFiltered);
}

/// Every source to search across, **pinned first** — for global search,
/// migration, and any other "search all sources" consumer. Pinned sources are
/// excluded from the grouped/filtered map (they get their own top section on the
/// Sources screen), so without prepending them here they'd be silently skipped.
@riverpod
AsyncValue<List<SourceDto>> searchableSources(Ref ref) {
  final mapData = ref.watch(sourceMapFilteredProvider);
  final pinned = ref.watch(pinnedSourcesProvider);
  return mapData.copyWithData((map) {
    final rest = <SourceDto>[];
    (map ?? const <String, List<SourceDto>>{}).forEach((key, value) {
      if (key != 'lastUsed') rest.addAll(value);
    });
    return [...pinned, ...rest];
  });
}

@riverpod
List<SourceDto>? sourceQuery(Ref ref, {String? query}) {
  final sourceMap = {...?ref.watch(sourceMapFilteredProvider).valueOrNull}
    ..remove('lastUsed');
  if (query.isNotBlank) {
    return sourceMap.values
        .expand((list) => list.where(
              (element) => element.name.query(query),
            ))
        .toList();
  }
  return sourceMap.values.expand((list) => list).toList();
}

/// The Sources-tab name filter. Mirrors [ExtensionQuery]: filters the grouped
/// source map by name while preserving the language grouping, so typing in the
/// Sources tab narrows the list instead of launching a global search.
@riverpod
AsyncValue<Map<String, List<SourceDto>>?> sourceMapFilteredAndQueried(Ref ref) {
  final sourceMapData = ref.watch(sourceMapFilteredProvider);
  final sourceMap = {...?sourceMapData.valueOrNull};
  final query = ref.watch(sourceSearchQueryProvider);
  if (query.isBlank) return sourceMapData;
  return sourceMapData.copyWithData(
    (e) => sourceMap.map<String, List<SourceDto>>(
      (key, value) => MapEntry(
        key,
        value.where((element) => element.name.query(query)).toList(),
      ),
    ),
  );
}

@riverpod
class SourceSearchQuery extends _$SourceSearchQuery
    with StateProviderMixin<String?> {
  @override
  String? build() => null;
}

@riverpod
class SourceLanguageFilter extends _$SourceLanguageFilter
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.sourceLanguageFilter);
}

@riverpod
class SourceLastUsed extends _$SourceLastUsed
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.sourceLastUsed);
}
