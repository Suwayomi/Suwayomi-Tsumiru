// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef ChapterDownloadProgress = ({int done, int total});

// Progress is in-memory: page rows appear only at commit, and interrupted work must not show stale progress.
class OfflineDownloadProgress
    extends Notifier<Map<int, ChapterDownloadProgress>> {
  @override
  Map<int, ChapterDownloadProgress> build() => const {};

  // Publish whole-percent changes only; faster page updates cannot move the rendered arc.
  void start(int chapterId, {required int total, int done = 0}) {
    final current = state[chapterId];
    if (current != null &&
        current.total == total &&
        _percent(done, total) == _percent(current.done, current.total) &&
        done != total) {
      return;
    }
    state = {...state, chapterId: (done: done, total: total)};
  }

  static int _percent(int done, int total) =>
      total <= 0 ? 0 : (done * 100) ~/ total;

  void clear(int chapterId) {
    if (!state.containsKey(chapterId)) return;
    state = {
      for (final e in state.entries)
        if (e.key != chapterId) e.key: e.value,
    };
  }
}

final offlineDownloadProgressProvider =
    NotifierProvider<
      OfflineDownloadProgress,
      Map<int, ChapterDownloadProgress>
    >(OfflineDownloadProgress.new);
