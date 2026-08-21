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
    this.onServerDownload,
    this.sessionProtected = const {},
    this.deleteWhileReadingSlots = 0,
    this.newlyReadChapterIds = const {},
    this.downloadProtectionWindow = false,
  });

  final OfflineDatabase db;
  final SafetyNetConfig nets;
  final Future<void> Function(int chapterId) onDownload;
  final Future<void> Function(int chapterId) onEvict;
  final DateTime now;

  /// Chapters read this session — shielded from rule eviction so finishing a
  /// chapter doesn't remove it from the device until the next launch.
  final Set<int> sessionProtected;

  /// The user's "delete finished chapters while reading" slot count. Every path
  /// that deletes a download has to honour it, not just the reader.
  final int deleteWhileReadingSlots;

  /// Chapter IDs that transitioned from unread → read during the most recent
  /// server sync (e.g. read in WebUI). Used by RC7 to apply the local
  /// delete-while-reading setting to externally-read chapters, exactly as if
  /// each had been finished in the in-app reader.
  final Set<int> newlyReadChapterIds;

  /// When true, the reconciler ensures the slots-1 most recently read chapters
  /// are present on device — downloading them if missing. Defaults to false to
  /// preserve existing behavior; only meaningful when deleteWhileReadingSlots >= 2.
  final bool downloadProtectionWindow;

  /// Called with chapters the keep-rule wants but the SERVER hasn't downloaded
  /// yet — enqueue a server download (server-client model: the server fetches
  /// the source, then a later reconcile pass pulls the device copy once
  /// serverIsDownloaded flips). Optional; when null those chapters are skipped
  /// (legacy behaviour).
  final Future<void> Function(Set<int> chapterIds)? onServerDownload;

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
      protected: {
        ...sessionProtected,
        ...readChaptersInDeleteWindow(chapters, deleteWhileReadingSlots),
      },
    );

    // Merge orphaned ids into the evict set.
    final toEvict = {...ev.evict, ...orphanedIds};

    // RC7: Sync-read eviction — for chapters that transitioned from unread to
    // read during this sync (e.g. read in WebUI), apply the local
    // delete-while-reading setting exactly as if each had been finished in the
    // in-app reader. Only newly-read chapters are considered, so old read
    // chapters already on the device are never touched unexpectedly.
    //
    // slots >= 1: the slots − 1 most-recently-read chapters among the newly-read
    //   batch are shielded by the same readChaptersInDeleteWindow window the
    //   reader uses. slots = 1 → delete the chapter itself; slots = 2 → keep
    //   the most recently read, delete the rest; etc.
    if (deleteWhileReadingSlots >= 1 && newlyReadChapterIds.isNotEmpty) {
      final newlyReadDownloaded = downloaded
          .where((c) => newlyReadChapterIds.contains(c.id))
          .toList();
      final readProtected =
          readChaptersInDeleteWindow(newlyReadDownloaded, deleteWhileReadingSlots);
      for (final c in newlyReadDownloaded) {
        if (!c.pinned &&
            !sessionProtected.contains(c.id) &&
            !readProtected.contains(c.id)) {
          toEvict.add(c.id);
        }
      }
    }

    // Build the toDownload set.
    // RC5: when the storage cap is active, do not emit downloads that would
    // push retained bytes over the cap — this ensures reconcile converges (a
    // fixed point) rather than triggering an evict→re-pull loop across passes.
    final byId = {for (final c in chapters) c.id: c};

    // Protection-window download: ensure the slots-1 most recently read
    // chapters are on-device when the user opted in. Meaningless for keep=off
    // (nothing is kept) and requires slots >= 2 (slots=1 means delete-all).
    final protectionWindowIds = downloadProtectionWindow &&
            deleteWhileReadingSlots >= 2 &&
            manga.keepRule != OfflineKeepRule.off
        ? readChaptersInDeleteWindow(chapters, deleteWhileReadingSlots)
        : const <int>{};

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
    final toServerDownload = <int>{};

    for (final id in {...desired, ...protectionWindowIds}) {
      final c = byId[id];
      if (c == null) continue;
      // Wanted but the server hasn't downloaded it yet: ask the server to
      // download it (it fetches the source); a later reconcile pass pulls the
      // device copy once serverIsDownloaded flips. Only when a handler is wired.
      if (!c.serverIsDownloaded) {
        if (onServerDownload != null &&
            c.deviceState != OfflineDeviceState.downloaded) {
          toServerDownload.add(id);
        }
        continue;
      }
      // Already on device — nothing to do.
      if (c.deviceState == OfflineDeviceState.downloaded) continue;
      // Re-planning a failed chapter every pass is what let one unfetchable
      // chapter keep a device and a server busy forever. Network failures park
      // as `downloading`, so nothing a reconnect should resume is stranded.
      if (c.deviceState == OfflineDeviceState.error) continue;

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
    if (onServerDownload != null && toServerDownload.isNotEmpty) {
      await onServerDownload!(toServerDownload);
    }

    return ReconcilePlan(
      toDownload: toDownload,
      toEvict: toEvict,
      overCapWarning: ev.overCapWarning,
    );
  }
}
