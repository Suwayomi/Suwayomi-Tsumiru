// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../domain/next_update/next_update_predictor.dart';
import 'manga_details_controller.dart';

part 'next_update_controller.g.dart';

/// Predicted next-chapter date for a manga, derived from its loaded chapter
/// list (upload/fetch timestamps). Null when there are no chapters yet.
@riverpod
NextUpdatePrediction? mangaNextUpdate(Ref ref, {required int mangaId}) {
  final chapters =
      ref.watch(mangaChapterListProvider(mangaId: mangaId)).valueOrNull;
  if (chapters == null || chapters.isEmpty) return null;
  final releases = <ChapterRelease>[
    for (final c in chapters)
      (
        uploadMs: int.tryParse(c.uploadDate) ?? 0,
        fetchMs: int.tryParse(c.fetchedAt) ?? 0,
      ),
  ];
  return predictNextUpdate(releases);
}
