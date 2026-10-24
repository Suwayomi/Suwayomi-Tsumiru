// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../constants/db_keys.dart';
import '../../../../../utils/mixin/shared_preferences_client_mixin.dart';
import '../../../../manga_book/domain/manga/manga_model.dart';
import '../../../../offline/data/offline_download_providers.dart';
import '../../../domain/duplicate_entry_mapper.dart';
import '../../../domain/duplicate_matcher.dart';
import '../../library/controller/library_manga_list.dart';

part 'library_duplicates_controller.g.dart';

/// Removes an entry and purges device downloads; failures may leave a partial removal.
typedef DuplicateEntryRemover = Future<void> Function(
    ProviderContainer container, int mangaId);

@riverpod
DuplicateEntryRemover duplicateEntryRemover(Ref ref) =>
    removeMangaFromLibraryAndPurge;

/// Hides removed entries and groups smaller than two without re-running the scan.
List<DupGroup> visibleDuplicateGroups(
  List<DupGroup> groups,
  Set<int> removedIds,
) {
  if (removedIds.isEmpty) return groups;
  final result = <DupGroup>[];
  for (final group in groups) {
    final remaining = [
      for (final id in group.memberIds)
        if (!removedIds.contains(id)) id,
    ];
    if (remaining.length >= 2) {
      result.add((
        header: group.header,
        memberIds: remaining,
        reasons: group.reasons,
      ));
    }
  }
  return result;
}

/// Reads the library once per build; only explicit rescan may repeat the O(n²) scan.
@riverpod
class LibraryDuplicates extends _$LibraryDuplicates {
  @override
  Future<List<DupGroup>> build({required bool checkDescriptions}) async {
    final library = await ref.read(libraryMangaListProvider.future);
    final entries = (library ?? const <MangaDto>[])
        .map(dupEntryFromManga)
        .toList();
    if (kIsWeb) {
      // compute() runs on the main thread on web; the chunked scan yields cooperatively.
      return scanForDuplicatesChunkedWeb(entries, checkDescriptions);
    }
    return compute(scanForDuplicates, (entries, checkDescriptions));
  }

  /// Refetches the library before scanning.
  Future<void> rescan() async {
    ref.invalidate(libraryMangaListProvider);
    ref.invalidateSelf();
  }
}

@riverpod
class LibraryDuplicatesCheckDescription
    extends _$LibraryDuplicatesCheckDescription
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(DBKeys.libraryDuplicatesCheckDescription);
}
