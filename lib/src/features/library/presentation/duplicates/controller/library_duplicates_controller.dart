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

/// Removes one library entry and purges its device downloads. Isolated behind a
/// provider so the removal flow can be exercised (including the partial-failure
/// path) without a live server or offline stack.
typedef DuplicateEntryRemover = Future<void> Function(
    ProviderContainer container, int mangaId);

@riverpod
DuplicateEntryRemover duplicateEntryRemover(Ref ref) =>
    removeMangaFromLibraryAndPurge;

/// Drops [removedIds] from each group's members and hides any group that falls
/// below two members — the on-screen filter after a removal, so the O(n²) scan
/// never has to re-run (Task 11 reads the library once).
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

/// Library-wide duplicate scan (#117).
///
/// Reads the library ONCE per build — never `watch`. A routine library
/// invalidation elsewhere (e.g. after a removal) must not silently re-trigger
/// this O(n²) scan; refresh only ever happens via the explicit [rescan].
@riverpod
class LibraryDuplicates extends _$LibraryDuplicates {
  @override
  Future<List<DupGroup>> build({required bool checkDescriptions}) async {
    final library = await ref.read(libraryMangaListProvider.future);
    final entries = (library ?? const <MangaDto>[])
        .map(dupEntryFromManga)
        .toList();
    if (kIsWeb) {
      // compute() is a main-thread no-op on web; the chunked scan yields
      // itself so the description pass never freezes the tab.
      return scanForDuplicatesChunkedWeb(entries, checkDescriptions);
    }
    return compute(scanForDuplicates, (entries, checkDescriptions));
  }

  /// Explicit refresh means server truth: refetch the library, then re-scan.
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
