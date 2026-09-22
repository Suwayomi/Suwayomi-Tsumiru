// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// These live outside offline_database.dart on purpose: riverpod_generator
// resolves provider signature types in a build phase where drift's generated
// part doesn't exist yet, so any type reached through that library reads as
// invalid. A part-free file keeps them resolvable everywhere.

/// On-device state of a chapter's bytes.
enum OfflineDeviceState {
  none,
  queued,
  downloading,
  downloaded,
  error,
  orphaned,
}

/// How many of a series' chapters to keep on this device automatically.
enum OfflineKeepRule { off, nUnread, allUnread, all }

/// A manga's own chapter sort axis. The first 4 mirror WebUI's `webUI_sortBy`
/// values verbatim — names ARE the wire strings (`.name` round-trips directly
/// to/from server meta, see webui_chapter_sort_meta.dart). `alphabetical` is
/// Tsumiru-only: it comes from the `flutter_chapterSortIsAlphabetical` flag
/// and is never written to `webUI_sortBy`.
enum ChapterSortAxis {
  source,
  chapterNumber,
  uploadedAt,
  fetchedAt,
  alphabetical,
}
