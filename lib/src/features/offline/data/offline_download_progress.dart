// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How far along one chapter's download is.
typedef ChapterDownloadProgress = ({int done, int total});

/// Live download progress, reported by whichever downloader is running.
///
/// The progress arc used to count page rows in the catalog, which only worked
/// while pages were published one at a time. Now a chapter's rows all appear at
/// once when it commits, so progress has to come from the downloader itself.
/// In-memory by design: this is a view of what is happening right now, and a
/// chapter that was interrupted should show as resumable, not frozen at 60%.
class OfflineDownloadProgress
    extends Notifier<Map<int, ChapterDownloadProgress>> {
  @override
  Map<int, ChapterDownloadProgress> build() => const {};

  /// A chapter began with a known page total, or advanced to [done] pages.
  ///
  /// Pages land far faster than a display can show them — a webtoon chapter
  /// over a fast link arrives at dozens a second, against a screen that redraws
  /// 60 times a second and an arc a person cannot read to better than a percent
  /// or so. Publishing every page made the UI rebuild for updates nobody could
  /// see, so only a visible change is published: the arc looks identical and
  /// most of the repaints stop happening.
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

  /// Whole percent, the finest step the arc actually renders.
  static int _percent(int done, int total) =>
      total <= 0 ? 0 : (done * 100) ~/ total;

  /// The chapter settled (committed, failed, cancelled or deleted) — the arc
  /// stops being live and the row's device state takes over.
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
