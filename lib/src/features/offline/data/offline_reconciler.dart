// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'offline_database.dart';
import 'reconcile_logic.dart';
import 'reconcile_types.dart';

/// Rough per-page byte estimate used to bound cap-gated downloads before any
/// real download sizes are known (cold start). Refined to real averages once
/// chapters are on device.
const _estimatedBytesPerPage = 256 * 1024;

/// Orchestrates a single reconcile pass for one manga: reads the offline
/// catalog, computes which chapters to download vs evict, invokes the injected
/// callbacks, and returns the [ReconcilePlan].
///
/// Callbacks are injected so the reconciler is fully testable without a real
/// download manager or filesystem.
class OfflineReconciler {
  OfflineReconciler({
    required this.db,
    required this.nets,
    required this.onDownload,
    required this.onEvict,
    required this.now,
  });

  final OfflineDatabase db;
  final SafetyNetConfig nets;
  final Future<void> Function(int chapterId) onDownload;
  final Future<void> Function(int chapterId) onEvict;
  final DateTime now;

  Future<ReconcilePlan> reconcileManga(int mangaId) async {
    final manga = await (db.select(db.offlineMangas)
          ..where((t) => t.id.equals(mangaId)))
        .getSingleOrNull();
    if (manga == null) return ReconcilePlan.empty;

    final chapters = await db.chaptersForManga(mangaId);

    // RC6: collect orphaned chapters (server-gone) — they must always be evicted.
    final orphanedIds = {
      for (final c in chapters)
        if (c.deviceState == OfflineDeviceState.orphaned) c.id,
    };

    // Only chapters in `downloaded` state are considered by applySafetyNets.
    final downloaded = chapters
        .where((c) => c.deviceState == OfflineDeviceState.downloaded)
        .toList();

    final desired =
        desiredChapterIds(chapters, manga.keepRule, manga.keepUnreadCount);

    final ev = applySafetyNets(
      downloaded: downloaded,
      desired: desired,
      nets: nets,
      now: now,
    );

    // Merge orphaned ids into the evict set.
    final toEvict = {...ev.evict, ...orphanedIds};

    // Build the toDownload set.
    // RC5: when the storage cap is active, do not emit downloads that would
    // push retained bytes over the cap — this ensures reconcile converges (a
    // fixed point) rather than triggering an evict→re-pull loop across passes.
    final byId = {for (final c in chapters) c.id: c};

    // Retained bytes after evictions (downloaded chapters not in toEvict).
    final retainedBytes = downloaded
        .where((c) => !toEvict.contains(c.id))
        .fold<int>(0, (sum, c) => sum + c.bytes);

    // Average byte size of currently-downloaded chapters — used to estimate
    // each new download's footprint so we can stop before exceeding the cap.
    final avgBytes = downloaded.isEmpty
        ? 0
        : downloaded.fold<int>(0, (s, c) => s + c.bytes) ~/ downloaded.length;

    var projectedBytes = retainedBytes;
    final toDownload = <int>{};

    for (final id in desired) {
      final c = byId[id];
      if (c == null) continue;
      // Unsatisfiable (design N3): server hasn't downloaded it yet — skip.
      if (!c.serverIsDownloaded) continue;
      // Already on device — nothing to do.
      if (c.deviceState == OfflineDeviceState.downloaded) continue;

      if (nets.storageCapEnabled) {
        // RC5 convergence guard: stop adding if there is no room.
        // If the cap is already met/exceeded by retained bytes, emit nothing.
        if (projectedBytes >= nets.storageCapBytes) break;
        // Cold-start fallback: when avgBytes is 0 (no chapters downloaded yet),
        // use a pageCount-derived estimate so the guard still bounds first-pass
        // downloads and avoids the evict↔re-pull oscillation the cap exists to
        // prevent.
        final estimate = avgBytes > 0
            ? avgBytes
            : c.pageCount * _estimatedBytesPerPage;
        if (estimate > 0 && projectedBytes + estimate > nets.storageCapBytes) {
          break;
        }
        projectedBytes += estimate;
      }

      toDownload.add(id);
    }

    for (final id in toEvict) {
      await onEvict(id);
    }
    for (final id in toDownload) {
      await onDownload(id);
    }

    return ReconcilePlan(
      toDownload: toDownload,
      toEvict: toEvict,
      overCapWarning: ev.overCapWarning,
    );
  }
}
