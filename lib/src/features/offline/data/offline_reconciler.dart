// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';

import '../../../utils/crash/diagnostics.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import 'offline_database.dart';
import 'reconcile_logic.dart';
import 'reconcile_types.dart';

// Cold-start estimate per page until actual chapter sizes are available.
const _estimatedBytesPerPage = 256 * 1024;

// Persisted server-fetch retry cap; restarts must not renew the budget.
const _maxServerFetchAttempts = 5;

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

  /// Shields session-read chapters from rule eviction only.
  final Set<int> sessionProtected;

  final int deleteWhileReadingSlots;

  /// Unread-to-read transitions from the latest sync, used for local delete-on-read.
  final Set<int> newlyReadChapterIds;

  /// Downloads the slots − 1 read-chapter window when enabled and slots >= 2.
  final bool downloadProtectionWindow;

  /// Queues missing server copies; null skips them until the server downloads them independently.
  final Future<void> Function(Set<int> chapterIds)? onServerDownload;

  Future<ReconcilePlan> reconcileManga(int mangaId) async {
    final manga = await (db.select(
      db.offlineMangas,
    )..where((t) => t.id.equals(mangaId))).getSingleOrNull();
    if (manga == null) return ReconcilePlan.empty;

    final chapters = await db.chaptersForManga(mangaId);

    final orphanedIds = {
      for (final c in chapters)
        if (c.deviceState == OfflineDeviceState.orphaned) c.id,
    };

    final downloaded = chapters
        .where((c) => c.deviceState == OfflineDeviceState.downloaded)
        .toList();

    final desired = desiredChapterIds(
      chapters,
      manga.keepRule,
      manga.keepUnreadCount,
      sortAxis: manga.chapterSortMode,
    );

    // nUnread limits new downloads, not retention of unread chapters already on disk.
    final retained = retainedChapterIds(
      chapters,
      manga.keepRule,
      manga.keepUnreadCount,
      sortAxis: manga.chapterSortMode,
    );

    final ev = applySafetyNets(
      downloaded: downloaded,
      desired: retained,
      nets: nets,
      now: now,
      protected: {
        ...sessionProtected,
        ...readChaptersInDeleteWindow(chapters, deleteWhileReadingSlots),
      },
    );

    // Orphan and sync-read eviction reasons override rule/safety-net reasons.
    final toEvict = {...ev.evict, ...orphanedIds};
    final evictReasons = <int, String>{
      for (final entry in ev.reasons.entries) entry.key: entry.value.name,
      for (final id in orphanedIds) id: 'orphaned',
    };

    // Apply delete-on-read only to new remote read transitions, preserving the slots − 1 window.
    if (deleteWhileReadingSlots >= 1 && newlyReadChapterIds.isNotEmpty) {
      final newlyReadDownloaded = downloaded
          .where((c) => newlyReadChapterIds.contains(c.id))
          .toList();
      final readProtected = readChaptersInDeleteWindow(
        newlyReadDownloaded,
        deleteWhileReadingSlots,
      );
      for (final c in newlyReadDownloaded) {
        if (!c.pinned &&
            !sessionProtected.contains(c.id) &&
            !readProtected.contains(c.id)) {
          toEvict.add(c.id);
          evictReasons[c.id] = 'sync-read';
        }
      }
    }

    // Bound downloads by retained bytes so cap eviction cannot trigger endless re-downloads.
    final byId = {for (final c in chapters) c.id: c};

    final protectionWindowIds =
        downloadProtectionWindow &&
            deleteWhileReadingSlots >= 2 &&
            manga.keepRule != OfflineKeepRule.off
        ? readChaptersInDeleteWindow(chapters, deleteWhileReadingSlots)
        : const <int>{};

    final retainedBytes = downloaded
        .where((c) => !toEvict.contains(c.id))
        .fold<int>(0, (sum, c) => sum + c.bytes);

    final avgBytes = downloaded.isEmpty
        ? 0
        : downloaded.fold<int>(0, (s, c) => s + c.bytes) ~/ downloaded.length;

    var projectedBytes = retainedBytes;
    final toDownload = <int>{};
    final toServerDownload = <int>{};

    for (final id in {...desired, ...protectionWindowIds}) {
      final c = byId[id];
      if (c == null || c.deviceState == OfflineDeviceState.error) continue;
      if (!c.serverIsDownloaded) {
        if (onServerDownload != null &&
            c.deviceState != OfflineDeviceState.downloaded) {
          if (c.serverFetchAttempts >= _maxServerFetchAttempts) {
            await db.transaction(() async {
              final latest = await db.chapterById(id);
              if (latest != null &&
                  latest.downloadGeneration == c.downloadGeneration &&
                  latest.deviceState != OfflineDeviceState.downloaded) {
                await db.setChapterDeviceState(id, OfflineDeviceState.error);
              }
            });
            recordDiagnostic(
              '[${DateTime.now().toIso8601String()}] offline-reconcile: '
              'giving-up-on-server-fetch mangaId=$mangaId chapterId=$id '
              'name="${c.name}" index=${c.chapterIndex} '
              'attempts=${c.serverFetchAttempts}/$_maxServerFetchAttempts '
              'serverIsDownloaded=false — excluded from further '
              'server-download requests\n',
            );
          } else {
            toServerDownload.add(id);
          }
        }
        continue;
      }
      if (c.serverFetchAttempts > 0) {
        await db.resetServerFetchAttempts(id);
      }
      if (c.deviceState == OfflineDeviceState.downloaded) continue;

      if (nets.storageCapEnabled) {
        if (projectedBytes >= nets.storageCapBytes) break;
        // Bound cold-start downloads by page estimates until measured chapter averages exist.
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

    if (toDownload.isNotEmpty || toServerDownload.isNotEmpty) {
      var alreadyOnDevice = 0;
      var errored = 0;
      for (final id in desired) {
        final st = byId[id]?.deviceState;
        if (st == OfflineDeviceState.downloaded) {
          alreadyOnDevice++;
        } else if (st == OfflineDeviceState.error) {
          errored++;
        }
      }
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-reconcile: '
        'plan mangaId=$mangaId keepRule=${manga.keepRule.name} '
        'keepN=${manga.keepUnreadCount} desired=${desired.length} '
        'toDownload=[${toDownload.join(',')}] '
        'toServerDownload=[${toServerDownload.join(',')}] '
        'alreadyOnDevice=$alreadyOnDevice errored=$errored\n',
      );
    }

    if (toEvict.isNotEmpty) {
      final byReason = <String, List<int>>{};
      for (final id in toEvict) {
        (byReason[evictReasons[id] ?? 'unknown'] ??= []).add(id);
      }
      final byReasonStr = byReason.entries
          .map((e) => '${e.key}=[${e.value.join(',')}]')
          .join(' ');
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-reconcile: '
        'evict mangaId=$mangaId keepRule=${manga.keepRule.name} '
        'keepN=${manga.keepUnreadCount} $byReasonStr\n',
      );
    }
    for (final id in toEvict) {
      await onEvict(id);
    }
    for (final id in toDownload) {
      await onDownload(id);
    }
    if (onServerDownload != null && toServerDownload.isNotEmpty) {
      await _askServerToFetch(mangaId, toServerDownload);
      for (final id in toServerDownload) {
        await db.transaction(() async {
          final chapter = await db.chapterById(id);
          if (chapter?.downloadGeneration == byId[id]?.downloadGeneration) {
            await db.incrementServerFetchAttempts(id);
          }
        });
        final c = byId[id];
        recordDiagnostic(
          '[${DateTime.now().toIso8601String()}] offline-reconcile: '
          'asking-server-to-fetch mangaId=$mangaId chapterId=$id '
          'name="${c?.name}" index=${c?.chapterIndex} '
          'attempt=${(c?.serverFetchAttempts ?? 0) + 1}/'
          '$_maxServerFetchAttempts\n',
        );
      }
    }

    return ReconcilePlan(
      toDownload: toDownload,
      toEvict: toEvict,
      overCapWarning: ev.overCapWarning,
    );
  }

  // One invalid id rejects the server batch; retry individually and charge only chapter rejections.
  Future<void> _askServerToFetch(int mangaId, Set<int> ids) async {
    Future<bool> ask(Set<int> batch) async {
      try {
        await onServerDownload!(batch);
        return true;
      } catch (e) {
        if (!_isChapterRejection(e)) rethrow;
        return false;
      }
    }

    if (await ask(ids)) return;
    for (final id in ids) {
      if (ids.length > 1 && await ask({id})) continue;
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-reconcile: '
        'server-rejected-fetch mangaId=$mangaId chapterId=$id\n',
      );
    }
  }
}

bool _isChapterRejection(Object error) {
  final cause = error is OperationMessageException ? error.exception : error;
  return cause is OperationException &&
      cause.graphqlErrors.isNotEmpty &&
      !isPermissionDenied(cause) &&
      !isAuthenticationRequired(cause);
}
