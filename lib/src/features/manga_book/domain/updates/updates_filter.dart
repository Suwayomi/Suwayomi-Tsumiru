// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Structural equality lets the screen detect filter changes between builds.
typedef UpdatesFilter = ({
  bool? downloaded,
  bool? unread,
  bool? started,
  bool? bookmarked,
});

const UpdatesFilter kNoUpdatesFilter = (
  downloaded: null,
  unread: null,
  started: null,
  bookmarked: null,
);
