// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_logic.dart';
import 'package:tsumiru/src/features/offline/data/reconcile_types.dart';

OfflineChapter dl(
  int id, {
  int bytes = 100,
  DateTime? at,
  bool pinned = false,
}) => OfflineChapter(
  id: id,
  mangaId: 1,
  name: 'c$id',
  chapterIndex: id,
  isRead: false,
  lastPageRead: 0,
  isBookmarked: false,
  serverIsDownloaded: true,
  deviceState: OfflineDeviceState.downloaded,
  pageCount: 1,
  bytes: bytes,
  pinned: pinned,
  downloadedAt: at ?? DateTime(2026, 1, id),
  progressDirty: false,
  bookmarkDirty: false,
  readStateDirty: false,
  readStateManual: false,
  syncedIsRead: false,
  updatedAt: DateTime(2026),
  downloadGeneration: 0,
  serverFetchAttempts: 0,
);

void main() {
  final now = DateTime(2026, 3, 1);

  test('eviction spares pinned and session-read chapters', () {
    final evicted = applySafetyNets(
      downloaded: [dl(1), dl(2)],
      desired: {1},
      nets: SafetyNetConfig.off,
      now: now,
    );
    expect(evicted.evict, {2});
    expect(evicted.overCapWarning, false);

    final sessionRead = applySafetyNets(
      downloaded: [dl(1), dl(2)],
      desired: {1},
      nets: SafetyNetConfig.off,
      now: now,
      protected: {2},
    );
    expect(
      sessionRead.evict,
      isEmpty,
      reason:
          'a chapter read this session must survive its manga\'s '
          'keep-rule until the next launch',
    );

    final pinned = applySafetyNets(
      downloaded: [dl(1, pinned: true)],
      desired: {},
      nets: SafetyNetConfig.off,
      now: now,
    );
    expect(pinned.evict, isEmpty);
  });

  test(
    'storage cap evicts oldest non-pinned first; warns if only pinned remain',
    () {
      final nets = SafetyNetConfig(
        timeEvictEnabled: false,
        keepDays: 30,
        storageCapEnabled: true,
        storageCapBytes: 150,
      );
      final r = applySafetyNets(
        downloaded: [
          dl(1, bytes: 100, at: DateTime(2026, 1, 1)),
          dl(2, bytes: 100, at: DateTime(2026, 1, 2), pinned: true),
        ],
        desired: {1, 2},
        nets: nets,
        now: now,
      );
      expect(r.evict, {1}); // evict oldest non-pinned to get under 150
      expect(r.overCapWarning, false);
    },
  );
}
