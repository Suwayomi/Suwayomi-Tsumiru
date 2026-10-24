// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Keep types outside drift libraries so riverpod_generator can resolve them before drift generation.

enum OfflineDeviceState {
  none,
  queued,
  downloading,
  downloaded,
  error,
  orphaned,
}

enum OfflineKeepRule { off, nUnread, allUnread, all }

// First four names are WebUI wire values; alphabetical uses a separate Tsumiru flag.
enum ChapterSortAxis {
  source,
  chapterNumber,
  uploadedAt,
  fetchedAt,
  alphabetical,
}
