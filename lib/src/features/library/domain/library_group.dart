// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Library grouping modes.
class LibraryGroup {
  static const byDefault = 0;
  static const bySource = 1;
  static const byStatus = 2;
  static const byTrackStatus = 3;
  static const ungrouped = 4;
}

/// Maps Suwayomi status strings → display order. Lower = shown first.
const statusOrder = <String, int>{
  'ONGOING': 1,
  'COMPLETED': 2,
  'PUBLISHING_FINISHED': 3,
  'LICENSED': 4,
  'ON_HIATUS': 5,
  'CANCELLED': 6,
  'UNKNOWN': 7,
};

/// Default library group type (BY_DEFAULT = 0).
/// Replaces the `DBKeys.libraryGroupType.initial as int` casts at call sites.
const int kDefaultLibraryGroupType = LibraryGroup.byDefault;
