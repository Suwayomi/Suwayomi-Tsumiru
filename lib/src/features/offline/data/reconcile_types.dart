// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Device-wide opt-in safety nets. Timestamp basis is downloadedAt (kept-N-days).
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

/// The outcome of a reconcile pass: chapters to fetch, chapters to evict, and
/// whether the storage cap can't be met without removing pinned chapters.
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
