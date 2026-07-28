// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// The Updates list filters, as one value. A record so equality is structural —
/// the screen compares it between builds to decide whether to refetch.
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
