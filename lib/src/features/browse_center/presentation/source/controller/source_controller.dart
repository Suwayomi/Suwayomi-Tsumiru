// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../../utils/mixin/state_provider_mixin.dart';
import '../../../../settings/presentation/browse/widgets/show_nsfw_switch/show_nsfw_switch.dart';
import '../../../data/source_repository/source_repository.dart';
import '../../../domain/content_rating.dart';
import '../../../domain/source/source_model.dart';

part 'source_controller.g.dart';

@riverpod
Future<List<SourceDto>?> sourceList(Ref ref) =>
    ref.watch(sourceRepositoryProvider).getSourceList();

/// Applies the NSFW source filter; an unset setting allows NSFW.
@riverpod
AsyncValue<List<SourceDto>?> visibleSourceList(Ref ref) {
  final showNsfw = ref.watch(showNSFWProvider).ifNull(true);
  return ref.watch(sourceListProvider).copyWithData(
        (list) => list == null || showNsfw
            ? list
            : [...list.where((e) => !isNsfwFromWarning(e.contentWarning))],
      );
}

/// Excludes hidden sources; the filter screen uses [visibleSourceList] so they can be unhidden.
@riverpod
AsyncValue<List<SourceDto>?> browsableSourceList(Ref ref) =>
    ref.watch(visibleSourceListProvider).copyWithData(
          (list) => list == null ? list : [...list.where((e) => !e.isHidden)],
        );

int _byName(SourceDto a, SourceDto b) =>
    a.name.toLowerCase().compareTo(b.name.toLowerCase());

List<SourceDto> pinnedSourcesFrom(List<SourceDto> sources) =>
    [...sources.where((e) => e.isPinned)]..sort(_byName);

/// Groups non-pinned sources by language, with a separate last-used bucket; sorts each by name.
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

/// Pinned sources ignore the active language filter.
@riverpod
List<SourceDto> pinnedSources(Ref ref) => pinnedSourcesFrom(
    ref.watch(browsableSourceListProvider).value ?? const []);

@riverpod
AsyncValue<Map<String, List<SourceDto>>> sourceMap(Ref ref) {
  final sourceListData = ref.watch(browsableSourceListProvider);
  final sourceLastUsed = ref.watch(sourceLastUsedProvider);
  return sourceListData.copyWithData(
    (data) => groupSourcesByLanguage(data ?? const [], sourceLastUsed),
  );
}

/// Includes hidden and pinned sources, grouped by language and sorted by visibility then name.
Map<String, List<SourceDto>> groupAllSourcesByLanguage(
  List<SourceDto> sources,
) {
  final sourceMap = <String, List<SourceDto>>{};
  for (final e in sources) {
    sourceMap.update(
      e.language?.code ?? "other",
      (value) => [...value, e],
      ifAbsent: () => [e],
    );
  }
  for (final list in sourceMap.values) {
    list.sort((a, b) => a.isHidden == b.isHidden
        ? _byName(a, b)
        : (a.isHidden ? 1 : -1));
  }
  return sourceMap;
}

/// Includes hidden sources so the filter screen can unhide them.
@riverpod
AsyncValue<Map<String, List<SourceDto>>> allSourcesByLanguage(Ref ref) {
  final sourceListData = ref.watch(visibleSourceListProvider);
  return sourceListData.copyWithData(
    (data) => groupAllSourcesByLanguage(data ?? const []),
  );
}

@riverpod
class SourceFilterLangMap extends _$SourceFilterLangMap {
  @override
  Map<String, bool> build() {
    final sourceMap = {...?ref.watch(sourceMapProvider).value};
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
  final sourceMap = {...?sourceMapData.value};
  final enabledLangList = [...?ref.watch(sourceLanguageFilterProvider)]..sort();
  for (final e in enabledLangList) {
    if (sourceMap.containsKey(e)) sourceMapFiltered[e] = sourceMap[e]!;
  }
  return sourceMapData.copyWithData((e) => sourceMapFiltered);
}

/// Includes pinned sources first; they are absent from the grouped source map.
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
  final sourceMap = {...?ref.watch(sourceMapFilteredProvider).value}
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

@riverpod
AsyncValue<Map<String, List<SourceDto>>?> sourceMapFilteredAndQueried(Ref ref) {
  final sourceMapData = ref.watch(sourceMapFilteredProvider);
  final sourceMap = {...?sourceMapData.value};
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

@Riverpod(keepAlive: true)
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
