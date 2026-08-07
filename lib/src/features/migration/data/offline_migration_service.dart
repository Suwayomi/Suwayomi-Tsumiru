// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../manga_book/domain/chapter/chapter_model.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../../offline/data/chapter_commit.dart';
import '../../offline/data/offline_database.dart';
import '../../offline/data/offline_page_store.dart';
import '../../offline/data/offline_sync.dart';
import '../domain/chapter_matcher.dart';
import '../domain/migration_models.dart';

/// Outcome of carrying device-local offline state onto a migration target.
class OfflineMigrationResult {
  const OfflineMigrationResult({
    this.movedDownloads = 0,
    this.refetchedDownloads = 0,
    this.unmatchedDownloads = 0,
    this.warnings = const [],
  });

  final int movedDownloads;
  final int refetchedDownloads;

  /// Source downloads with no chapter-number match on the target — nothing to
  /// move and nothing to refetch (the chapter simply doesn't exist on B).
  final int unmatchedDownloads;
  final List<String> warnings;
}

/// Carries device-local offline state (keep-rule + downloaded files) across a
/// migration. Reader settings are server-side meta, copied separately in
/// [MigrationRepository.copyMangaData].
///
/// Self-contained and idempotent (skips already-downloaded target chapters), so
/// it's safely re-runnable from crash recovery. Invoke after a successful copy
/// and before source removal — a failure here must leave the source intact.
class OfflineMigrationService {
  OfflineMigrationService({
    required this.db,
    required this.pageStore,
    required this.sync,
    required this.fetchManga,
    required this.fetchChapters,
    required this.reconcileTarget,
  });

  final OfflineDatabase db;
  final OfflinePageStore pageStore;
  final OfflineSync sync;
  final Future<MangaDto?> Function(int mangaId) fetchManga;
  final Future<List<ChapterDto>?> Function(int mangaId) fetchChapters;

  /// Reconcile pass on the target: no-op for the chapters we just moved, and
  /// enqueues a server download for anything we pinned but couldn't move.
  final Future<void> Function(int toMangaId) reconcileTarget;

  Future<OfflineMigrationResult> migrate({
    required int fromMangaId,
    required int toMangaId,
    required MigrationOption options,
  }) async {
    if (!options.migrateDownloads && !options.migrateOfflineSettings) {
      return const OfflineMigrationResult();
    }
    final warnings = <String>[];

    // Seed the target catalog rows to attach the keep-rule and downloads to;
    // preserves device-managed columns, so this is safe even if B already had
    // offline content.
    // Ordered against push acks: captured before the fetches go out.
    final fetchGen = sync.syncGeneration;
    final targetManga = await fetchManga(toMangaId);
    if (targetManga == null) {
      return const OfflineMigrationResult(
        warnings: ['Could not read the target for offline migration.'],
      );
    }
    final targetChapters = await fetchChapters(toMangaId) ?? const [];
    await sync.syncManga(targetManga, fetchedAtGen: fetchGen);
    await sync.syncChapters(targetChapters);

    if (options.migrateOfflineSettings) {
      final source = await db.mangaById(fromMangaId);
      if (source != null && source.keepRule != OfflineKeepRule.off) {
        await db.setKeepRule(
            toMangaId, source.keepRule, source.keepUnreadCount);
      }
    }

    var moved = 0;
    var refetched = 0;
    var unmatched = 0;
    if (options.migrateDownloads) {
      final result = await _migrateDownloads(
        fromMangaId: fromMangaId,
        toMangaId: toMangaId,
        targetChapters: targetChapters,
        keepSource: !options.deleteSource,
        warnings: warnings,
      );
      moved = result.moved;
      refetched = result.refetched;
      unmatched = result.unmatched;
    }

    // Apply the keep-rule and pick up the pinned-but-not-moved refetches.
    await reconcileTarget(toMangaId);

    // Migrate: drop the source's keep-rule and pins so the runner's post-removal
    // reconcile evicts every remaining source download. Copy leaves it untouched.
    if (options.deleteSource) {
      await db.setKeepRule(fromMangaId, OfflineKeepRule.off,
          (await db.mangaById(fromMangaId))?.keepUnreadCount ?? 3);
      await db.unpinChaptersForManga(fromMangaId);
    }

    return OfflineMigrationResult(
      movedDownloads: moved,
      refetchedDownloads: refetched,
      unmatchedDownloads: unmatched,
      warnings: warnings,
    );
  }

  Future<({int moved, int refetched, int unmatched})> _migrateDownloads({
    required int fromMangaId,
    required int toMangaId,
    required List<ChapterDto> targetChapters,
    required bool keepSource,
    required List<String> warnings,
  }) async {
    final sourceDownloaded = await db.downloadedChaptersForManga(fromMangaId);
    if (sourceDownloaded.isEmpty) return (moved: 0, refetched: 0, unmatched: 0);

    // Chapter numbers live on the server DTO, not the offline row, so match the
    // downloaded source chapters against the source DTO list for their numbers.
    final sourceChapters = await fetchChapters(fromMangaId) ?? const [];
    final downloadedIds = {for (final c in sourceDownloaded) c.id};
    final sourceStates = [
      for (final c in sourceChapters)
        if (downloadedIds.contains(c.id)) _state(c),
    ];
    final pairs = matchChaptersByNumber(
      source: sourceStates,
      target: [for (final c in targetChapters) _state(c)],
    );
    final targetById = {for (final c in targetChapters) c.id: c};
    final sourceOfflineById = {for (final c in sourceDownloaded) c.id: c};

    var moved = 0;
    var refetched = 0;
    for (final pair in pairs) {
      final src = sourceOfflineById[pair.fromId];
      try {
        final transferred = await _transferOne(
          fromMangaId: fromMangaId,
          fromChapterId: pair.fromId,
          toMangaId: toMangaId,
          toChapterId: pair.toId,
          downloadedAt: src?.downloadedAt ?? DateTime.now(),
          keepSource: keepSource,
        );
        if (transferred) moved++;
      } catch (e) {
        // Couldn't reuse the bytes — pin the target so the reconcile pass
        // re-fetches it from the server.
        await db.setChapterPinned(pair.toId, true);
        refetched++;
        warnings.add('Re-downloading "${targetById[pair.toId]?.name ?? pair.toId}" '
            '(couldn\'t move the existing copy).');
      }
    }
    final unmatched = downloadedIds.length - pairs.length;
    return (moved: moved, refetched: refetched, unmatched: unmatched);
  }

  /// Carry one chapter's downloaded pages onto the target: copy into the
  /// target's staging area, commit it, then drop the source.
  ///
  /// Never a bare rename. A rename destroys the source before the target's
  /// catalog write lands, and a crash in that window leaves a complete
  /// directory under a `none` row — which recovery would rightly delete as a
  /// delete the user made, taking the only copy with it. Copying costs a
  /// duplicate of one chapter during a rare, user-initiated operation; the
  /// rename costs the chapter.
  ///
  /// Both chapters are held for the whole sequence, so a download or an
  /// eviction can't publish into either one halfway through.
  Future<bool> _transferOne({
    required int fromMangaId,
    required int fromChapterId,
    required int toMangaId,
    required int toChapterId,
    required DateTime downloadedAt,
    required bool keepSource,
  }) =>
      ChapterFileLock.runPair(fromChapterId, toChapterId, () async {
        final target = await db.chapterById(toChapterId);
        // Only an empty or already-finished target is safe to write over. A
        // queued/downloading one has a producer of its own holding staging, and
        // migration is not entitled to commit on top of it.
        if (target == null ||
            (target.deviceState != OfflineDeviceState.none &&
                target.deviceState != OfflineDeviceState.downloaded)) {
          return false;
        }
        if (target.deviceState == OfflineDeviceState.downloaded) return false;
        if (await pageStore.readManifest(toMangaId, toChapterId) != null) {
          return false; // a live download owns this chapter's staging
        }

        await pageStore.stageChapterCopy(
          fromMangaId,
          fromChapterId,
          toMangaId,
          toChapterId,
          generation: target.downloadGeneration,
        );
        final pages = await pageStore.commitStaging(toMangaId, toChapterId);
        if (pages == null) {
          await pageStore.deleteStaging(toMangaId, toChapterId);
          throw const OfflineTransferException('staged copy was incomplete');
        }
        await db.commitTransferredChapter(
          toChapterId: toChapterId,
          pages: pages,
          downloadedAt: downloadedAt,
          // Pin so the move survives regardless of the target's keep-rule.
          pinned: true,
          clearSourceChapterId: keepSource ? null : fromChapterId,
        );
        // The target owns the bytes now, so the source can go. Until this line
        // a crash leaves both copies, which recovery settles.
        if (!keepSource) {
          await pageStore.deleteChapter(fromMangaId, fromChapterId);
        }
        return true;
      });

  ChapterState _state(ChapterDto c) => ChapterState(
        id: c.id,
        chapterNumber: c.chapterNumber,
        name: c.name,
        isRead: c.isRead,
        isBookmarked: c.isBookmarked,
        lastPageRead: c.lastPageRead,
      );
}
