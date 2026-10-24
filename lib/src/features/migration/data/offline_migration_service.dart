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

class OfflineMigrationResult {
  const OfflineMigrationResult({
    this.movedDownloads = 0,
    this.refetchedDownloads = 0,
    this.unmatchedDownloads = 0,
    this.warnings = const [],
  });

  final int movedDownloads;
  final int refetchedDownloads;

  /// Downloads with no target chapter-number match cannot be moved or refetched.
  final int unmatchedDownloads;
  final List<String> warnings;
}

enum _TransferOutcome {
  moved,

  alreadyPresent,

  /// Caller pins the target for refetch when bytes cannot be reused.
  refused,
}

/// Idempotently carries offline state after server copy and before source removal.
class OfflineMigrationService {
  OfflineMigrationService({
    required this.db,
    required this.pageStore,
    required this.sync,
    required this.fetchManga,
    required this.fetchChapters,
    required this.reconcileTarget,
    this.withOwnership,
  });

  final Future<T> Function<T>(Future<T> Function() action)? withOwnership;
  final OfflineDatabase db;
  final OfflinePageStore pageStore;
  final OfflineSync sync;
  final Future<MangaDto?> Function(int mangaId) fetchManga;
  final Future<List<ChapterDto>?> Function(int mangaId) fetchChapters;

  /// Reconciles the target, refetching pinned chapters whose bytes could not be moved.
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

    // Capture sync generation before fetching so catalog writes respect push acknowledgments.
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
          toMangaId,
          source.keepRule,
          source.keepUnreadCount,
        );
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

    await reconcileTarget(toMangaId);

    // Migrate clears source rules and pins for eviction; Copy retains them.
    if (options.deleteSource) {
      await db.setKeepRule(
        fromMangaId,
        OfflineKeepRule.off,
        (await db.mangaById(fromMangaId))?.keepUnreadCount ?? 3,
      );
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

    // Offline rows lack chapter numbers, so match downloads through server DTOs.
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
      var outcome = _TransferOutcome.refused;
      try {
        outcome = await _transferOne(
          fromMangaId: fromMangaId,
          fromChapterId: pair.fromId,
          toMangaId: toMangaId,
          toChapterId: pair.toId,
          downloadedAt: src?.downloadedAt ?? DateTime.now(),
          keepSource: keepSource,
        );
      } catch (_) {
        outcome = _TransferOutcome.refused;
      }
      switch (outcome) {
        case _TransferOutcome.moved:
          moved++;
        case _TransferOutcome.alreadyPresent:
          break; // the target already has it; nothing to carry or re-fetch
        case _TransferOutcome.refused:
          // Pin refused transfers so reconciliation refetches their bytes.
          await db.setChapterPinned(pair.toId, true);
          refetched++;
          warnings.add(
            'Re-downloading "${targetById[pair.toId]?.name ?? pair.toId}" '
            '(couldn\'t move the existing copy).',
          );
      }
    }
    final unmatched = downloadedIds.length - pairs.length;
    return (moved: moved, refetched: refetched, unmatched: unmatched);
  }

  // Copy into staging before committing; hold both chapters so crashes retain a recoverable copy.
  Future<_TransferOutcome> _transferOne({
    required int fromMangaId,
    required int fromChapterId,
    required int toMangaId,
    required int toChapterId,
    required DateTime downloadedAt,
    required bool keepSource,
  }) async {
    Future<_TransferOutcome> transfer() => _transferOneOwned(
      fromMangaId: fromMangaId,
      fromChapterId: fromChapterId,
      toMangaId: toMangaId,
      toChapterId: toChapterId,
      downloadedAt: downloadedAt,
      keepSource: keepSource,
    );
    final ownership = withOwnership;
    return ownership == null ? transfer() : ownership(transfer);
  }

  Future<_TransferOutcome> _transferOneOwned({
    required int fromMangaId,
    required int fromChapterId,
    required int toMangaId,
    required int toChapterId,
    required DateTime downloadedAt,
    required bool keepSource,
  }) => ChapterFileLock.runPair(fromChapterId, toChapterId, () async {
    final target = await db.chapterById(toChapterId);
    if (target == null) return _TransferOutcome.refused;
    if (target.deviceState == OfflineDeviceState.downloaded) {
      return _TransferOutcome.alreadyPresent;
    }
    // Only an empty target is safe; queued/downloading chapters have another staging producer.
    if (target.deviceState != OfflineDeviceState.none) {
      return _TransferOutcome.refused;
    }
    if (await pageStore.readManifest(toMangaId, toChapterId) != null) {
      return _TransferOutcome.refused; // staging is spoken for
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
      return _TransferOutcome.refused;
    }
    await db.commitTransferredChapter(
      toChapterId: toChapterId,
      pages: pages,
      downloadedAt: downloadedAt,
      // Preserve the download regardless of the target keep-rule.
      pinned: true,
      clearSourceChapterId: keepSource ? null : fromChapterId,
    );
    // Delete source bytes only after the target owns a committed copy.
    if (!keepSource) {
      await pageStore.deleteChapter(fromMangaId, fromChapterId);
    }
    return _TransferOutcome.moved;
  });

  ChapterState _state(ChapterDto c) => ChapterState(
    id: c.id,
    chapterNumber: c.chapterNumber,
    name: c.name,
    isRead: c.user.isRead,
    isBookmarked: c.user.isBookmarked,
    lastPageRead: c.user.lastPageRead,
  );
}
