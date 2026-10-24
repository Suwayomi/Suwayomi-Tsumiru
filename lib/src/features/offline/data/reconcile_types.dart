// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Time eviction uses downloadedAt, not reading timestamps.
class SafetyNetConfig {
  const SafetyNetConfig({
    required this.timeEvictEnabled,
    required this.keepDays,
    required this.storageCapEnabled,
    required this.storageCapBytes,
  });

  final bool timeEvictEnabled;
  final int keepDays;
  final bool storageCapEnabled;
  final int storageCapBytes;

  static const off = SafetyNetConfig(
    timeEvictEnabled: false,
    keepDays: 30,
    storageCapEnabled: false,
    storageCapBytes: 0,
  );
}

/// overCapWarning means meeting the cap would require evicting pinned chapters.
class ReconcilePlan {
  const ReconcilePlan({
    required this.toDownload,
    required this.toEvict,
    required this.overCapWarning,
  });

  final Set<int> toDownload;
  final Set<int> toEvict;
  final bool overCapWarning;

  static const empty =
      ReconcilePlan(toDownload: {}, toEvict: {}, overCapWarning: false);
}
