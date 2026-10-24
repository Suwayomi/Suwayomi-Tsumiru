// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Persisted as DBKeys.libraryGroupType; values are frozen and new modes must be appended.
class LibraryGroup {
  static const byDefault = 0;
  static const bySource = 1;
  static const byStatus = 2;
  static const byTrackStatus = 3;
  static const ungrouped = 4;

  /// Source genres and user tags; one manga can belong to multiple groups.
  static const byTag = 5;
  static const byLanguage = 6;

  /// Display order, independent of persisted values.
  static const all = <int>[
    byDefault,
    byTag,
    bySource,
    byStatus,
    byTrackStatus,
    byLanguage,
    ungrouped,
  ];

  static bool isGrouped(int type) => type != ungrouped;
}

const statusOrder = <String, int>{
  'ONGOING': 1,
  'COMPLETED': 2,
  'PUBLISHING_FINISHED': 3,
  'LICENSED': 4,
  'ON_HIATUS': 5,
  'CANCELLED': 6,
  'UNKNOWN': 7,
};

const int kDefaultLibraryGroupType = LibraryGroup.byDefault;
