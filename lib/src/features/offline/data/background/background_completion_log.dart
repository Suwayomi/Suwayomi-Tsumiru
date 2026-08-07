// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../utils/logger/logger.dart';
import '../chapter_commit.dart';
import '../offline_database.dart';
import '../offline_page_store.dart';
import '../offline_paths.dart';
import '../offline_types.dart';

sealed class LogEntry {
  const LogEntry();
}

class ChapterEntry extends LogEntry {
  const ChapterEntry(
      this.chapterId, this.status, this.pages, this.bytes, this.generation);
  final int chapterId, pages, bytes, generation;
  final String status; // downloaded | error | authFailed | offline
}

/// A chapter was deleted at the given (post-bump) generation; replay wipes
/// prior accumulation for it, so even a stale entry appended after this is
/// discarded rather than applied.
class DeletedEntry extends LogEntry {
  const DeletedEntry(this.chapterId, this.generation);
  final int chapterId, generation;
}

class DrainedEntry extends LogEntry {
  const DrainedEntry();
}

/// A chapter the background catch-up downloaded that drift has never seen —
/// carries the metadata replay needs to CREATE the row. Adoption is the one
/// sanctioned exception to never-resurrect: it only applies when the row is
/// missing outright (a foreground delete keeps its row as `none`), the manga
/// still has an active keep rule, and the serverId matches the catalog.
class AdoptChapterEntry extends LogEntry {
  const AdoptChapterEntry({
    required this.chapterId,
    required this.mangaId,
    required this.serverId,
    required this.name,
    required this.chapterIndex,
    required this.chapterNumber,
    required this.pageCount,
    required this.bytes,
    required this.isRead,
  });
  final int chapterId, mangaId, chapterIndex, pageCount, bytes;
  final String serverId, name;
  final double chapterNumber;
  final bool isRead;
}

/// Append-only JSONL record of background-download progress — the durable
/// record of what the worker isolates decided, replayed into drift on
/// resume/launch. A torn final line (killed mid-write) is silently discarded
/// on parse.
///
/// Only terminal, adoption and tombstone entries live here. Per-page lines used
/// to be appended (and fsynced) as each page landed; they are gone, because the
/// pages themselves are no longer the thing that makes a chapter complete — the
/// staging manifest is, and it is written once per chapter.
class BackgroundCompletionLog {
  BackgroundCompletionLog(this.file);
  final File file;

  Future<void> _append(Map<String, Object?> obj) async {
    await file.parent.create(recursive: true);
    await file.writeAsString('${jsonEncode(obj)}\n',
        mode: FileMode.append, flush: true);
  }

  Future<void> appendChapter({
    required int chapterId,
    required String status,
    required int pages,
    required int bytes,
    int generation = 0,
  }) =>
      _append({'t': 'chapter', 'c': chapterId, 's': status, 'pages': pages, 'bytes': bytes, 'g': generation});

  Future<void> appendDeleted(int chapterId, int generation) =>
      _append({'t': 'deleted', 'c': chapterId, 'g': generation});

  Future<void> appendDrained() => _append({'t': 'drained'});

  Future<void> appendAdopt(AdoptChapterEntry e) => _append({
        't': 'adopt',
        'c': e.chapterId,
        'm': e.mangaId,
        'srv': e.serverId,
        'n': e.name,
        'idx': e.chapterIndex,
        'num': e.chapterNumber,
        'pages': e.pageCount,
        'bytes': e.bytes,
        'read': e.isRead,
      });

  Future<List<LogEntry>> parse() async {
    if (!await file.exists()) return const [];
    final lines = await file.readAsLines();
    final out = <LogEntry>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, Object?> j;
      try {
        j = jsonDecode(line) as Map<String, Object?>;
      } catch (_) {
        continue; // torn/partial line — discard
      }
      switch (j['t']) {
        // 'page': written by builds before chapters became atomic. Ignored —
        // recovery reads the filesystem, which is the same truth without the
        // fsync per page.
        case 'chapter':
          out.add(ChapterEntry(j['c'] as int, j['s'] as String, j['pages'] as int, j['bytes'] as int, j['g'] as int? ?? 0));
        case 'deleted':
          out.add(DeletedEntry(j['c'] as int, j['g'] as int? ?? 0));
        case 'drained':
          out.add(const DrainedEntry());
        case 'adopt':
          out.add(AdoptChapterEntry(
            chapterId: j['c'] as int,
            mangaId: j['m'] as int,
            serverId: j['srv'] as String? ?? '',
            name: j['n'] as String? ?? '',
            chapterIndex: (j['idx'] as num?)?.toInt() ?? 0,
            chapterNumber: (j['num'] as num?)?.toDouble() ?? -1,
            pageCount: (j['pages'] as num?)?.toInt() ?? 0,
            bytes: (j['bytes'] as num?)?.toInt() ?? 0,
            isRead: j['read'] as bool? ?? false,
          ));
      }
    }
    return out;
  }

  Future<void> truncate() async {
    if (await file.exists()) await file.writeAsString('', flush: true);
  }
}

/// Apply a worker's non-success terminal event to drift. A success no longer
/// arrives this way — a chapter becomes `downloaded` by being committed, never
/// by a log line claiming it is. [eventGeneration] older than the chapter's
/// persisted `downloadGeneration` (bumped on each delete) is dropped, so a
/// stale event from a deleted/re-queued chapter can't mark it failed.
Future<void> applyBackgroundTerminalState({
  required OfflineDatabase db,
  required int chapterId,
  required String status,
  int eventGeneration = 0,
}) async {
  if (status != 'error' && status != 'authFailed') return;
  await db.transaction(() async {
    final c = await db.chapterById(chapterId);
    if (c == null || c.deviceState == OfflineDeviceState.none) return;
    if (eventGeneration < c.downloadGeneration) return; // stale generation
    if (c.deviceState == OfflineDeviceState.downloading) {
      await db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
    }
  });
}

/// Reconcile the catalog with what is actually on disk, then apply whatever the
/// background workers recorded.
///
/// Recovery is state-driven rather than log-driven: the workers only ever fill
/// staging directories, so the durable question at launch is "what does each
/// chapter's directory look like, and what does its row say" — which survives a
/// lost log, a killed worker, and a crash between the commit rename and its
/// catalog write.
Future<void> replayCompletionLog({
  required OfflineDatabase db,
  required OfflinePaths paths,
  required OfflinePageStore store,
  required BackgroundCompletionLog log,
  String? catalogServerId,
}) async {
  final entries = await log.parse();

  // Adoptions first: they create rows drift has never seen, so the recovery
  // pass below sees a row to attach the files to rather than an orphan.
  await _adoptCatchupChapters(
    db: db,
    store: store,
    entries: entries,
    catalogServerId: catalogServerId,
  );

  await _recoverChaptersOnDisk(db: db, paths: paths, store: store);

  await _applyTerminalEntries(db: db, entries: entries);

  await log.truncate();
}

/// Create rows for chapters the background catch-up downloaded while drift knew
/// nothing about them. The files themselves are published by the recovery pass;
/// this only decides whether we are willing to own them at all.
Future<void> _adoptCatchupChapters({
  required OfflineDatabase db,
  required OfflinePageStore store,
  required List<LogEntry> entries,
  required String? catalogServerId,
}) async {
  final adoptions = <int, AdoptChapterEntry>{};
  for (final e in entries) {
    if (e is AdoptChapterEntry) adoptions[e.chapterId] = e;
  }
  for (final a in adoptions.values) {
    // A row that already exists took its own path (including a `none` row from
    // a foreground delete, which recovery honours by deleting the files).
    if (await db.chapterById(a.chapterId) != null) continue;
    final manga = await (db.select(db.offlineMangas)
          ..where((t) => t.id.equals(a.mangaId)))
        .getSingleOrNull();
    final accepted = manga != null &&
        manga.keepRule != OfflineKeepRule.off &&
        catalogServerId != null &&
        a.serverId == catalogServerId;
    if (!accepted) {
      // Refusals clean up here, under replay's ownership — a refused download
      // has no row, so eviction can't see it and it would sit on disk forever.
      await store.deleteChapter(a.mangaId, a.chapterId);
      continue;
    }
    await db.transaction(() async {
      if (await db.chapterById(a.chapterId) != null) return;
      await db.upsertChapterMetadata(
        id: a.chapterId,
        mangaId: a.mangaId,
        name: a.name,
        chapterIndex: a.chapterIndex,
        isRead: a.isRead,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: a.pageCount,
        updatedAt: DateTime.now(),
        chapterNumber: a.chapterNumber < 0 ? null : a.chapterNumber,
        syncedIsRead: a.isRead,
      );
      // Claim it as ours before the commit runs. If the files turn out to be
      // incomplete, the row stays resumable instead of being thrown away.
      await db.setChapterDeviceState(
          a.chapterId, OfflineDeviceState.downloading);
    });
  }
}

/// Walk every chapter directory on disk and settle it against its catalog row.
///
/// | on disk          | row                    | what happens                  |
/// |------------------|------------------------|-------------------------------|
/// | anything         | `none` or missing      | both directories deleted      |
/// | final, complete  | `downloaded`           | nothing                       |
/// | final, complete  | anything else          | adopted — the commit rename landed, its catalog write didn't |
/// | final, legacy    | `downloaded`           | grandfathered, trusted as-is  |
/// | final, legacy    | anything else          | cleared, so it re-downloads   |
/// | staging complete | not `none`             | committed                     |
/// | staging partial  | not `none`             | left alone, resumed later     |
///
/// Driven off the filesystem rather than the catalog: the directories that
/// exist are bounded by what has actually been downloaded, where the chapter
/// table is the size of the whole library.
Future<void> _recoverChaptersOnDisk({
  required OfflineDatabase db,
  required OfflinePaths paths,
  required OfflinePageStore store,
}) async {
  for (final dir in await _chapterDirsOnDisk(paths)) {
    try {
      await ChapterFileLock.run(dir.chapterId, () async {
        final row = await db.chapterById(dir.chapterId);
        // Never resurrect: a `none` row is a delete the user made, and a
        // missing row means nothing authorised these files (adoption above is
        // the one sanctioned exception, and it has already run).
        if (row == null || row.deviceState == OfflineDeviceState.none) {
          await store.deleteChapter(dir.mangaId, dir.chapterId);
          return;
        }

        if (dir.hasFinal) {
          final committed =
              await store.inspectCommitted(dir.mangaId, dir.chapterId);
          switch (committed.state) {
            case ChapterDirState.complete:
              // Already settled, or the rename landed and the catalog write
              // didn't — either way the rows are cheap to reassert.
              if (row.deviceState != OfflineDeviceState.downloaded) {
                await db.commitDownloadedChapter(
                  chapterId: dir.chapterId,
                  pages: committed.pages,
                  downloadedAt: row.downloadedAt ?? DateTime.now(),
                );
                logger.i('Offline: adopted committed chapter '
                    '${dir.chapterId} (${committed.pages.length} pages)');
              }
              // Staging alongside a complete final dir is a superseded attempt.
              await store.deleteStaging(dir.mangaId, dir.chapterId);
              return;
            case ChapterDirState.legacy:
              if (row.deviceState == OfflineDeviceState.downloaded) {
                // Downloaded before chapters were atomic. Nothing on disk can
                // prove it whole, and re-fetching everyone's library to find
                // out is not a trade worth making — trust it.
                return;
              }
              // Interrupted under the old scheme, so its pages can't be
              // verified or safely resumed. One re-download, once, on upgrade.
              await _clearForRefetch(db, store, dir.mangaId, dir.chapterId);
            case ChapterDirState.incomplete:
              await _clearForRefetch(db, store, dir.mangaId, dir.chapterId);
            case ChapterDirState.absent:
              break;
          }
        }

        if (dir.hasStaging) {
          await commitStagedChapterHoldingLock(
            db: db,
            store: store,
            mangaId: dir.mangaId,
            chapterId: dir.chapterId,
          );
        }
      });
    } catch (e) {
      // One unreadable directory must not stop the rest of the library from
      // being recovered.
      logger.e('Offline: recovery skipped for chapter ${dir.chapterId}: $e');
    }
  }
}

/// Drop a chapter's unusable files and rows, leaving the state that makes the
/// downloader pick it up again.
Future<void> _clearForRefetch(
  OfflineDatabase db,
  OfflinePageStore store,
  int mangaId,
  int chapterId,
) async {
  await store.deleteChapter(mangaId, chapterId);
  await db.transaction(() async {
    await (db.delete(db.offlinePages)
          ..where((t) => t.chapterId.equals(chapterId)))
        .go();
    await db.setChapterDeviceState(chapterId, OfflineDeviceState.queued,
        bytes: 0);
  });
}

/// Apply the workers' failure records, scoped to the newest generation seen per
/// chapter so an entry from before a delete can't mark a re-queued chapter
/// failed.
Future<void> _applyTerminalEntries({
  required OfflineDatabase db,
  required List<LogEntry> entries,
}) async {
  final terminal = <int, String>{};
  final gen = <int, int>{};

  void advance(int chapterId, int g) {
    if (g > (gen[chapterId] ?? 0)) {
      gen[chapterId] = g;
      terminal.remove(chapterId);
    }
  }

  for (final e in entries) {
    switch (e) {
      case ChapterEntry(:final chapterId, :final status, :final generation):
        advance(chapterId, generation);
        if (generation < (gen[chapterId] ?? 0)) break; // stale generation
        terminal[chapterId] = status;
      case DeletedEntry(:final chapterId, :final generation):
        advance(chapterId, generation);
        terminal.remove(chapterId);
      case DrainedEntry():
      case AdoptChapterEntry():
        break;
    }
  }

  for (final entry in terminal.entries) {
    await applyBackgroundTerminalState(
      db: db,
      chapterId: entry.key,
      status: entry.value,
      eventGeneration: gen[entry.key] ?? 0,
    );
  }
}

/// Every chapter directory under the offline base dir, final and staging.
Future<List<({int mangaId, int chapterId, bool hasFinal, bool hasStaging})>>
    _chapterDirsOnDisk(OfflinePaths paths) async {
  final found = <int, ({int mangaId, bool hasFinal, bool hasStaging})>{};
  final base = Directory(paths.baseDir);
  if (!await base.exists()) return const [];
  await for (final mangaEntity in base.list()) {
    if (mangaEntity is! Directory) continue;
    // Skips `covers` and anything else that isn't a manga id.
    final mangaId = int.tryParse(p.basename(mangaEntity.path));
    if (mangaId == null) continue;
    await for (final chapterEntity in mangaEntity.list()) {
      if (chapterEntity is! Directory) continue;
      final name = p.basename(chapterEntity.path);
      final staging = name.endsWith('.part');
      final chapterId = int.tryParse(
          staging ? name.substring(0, name.length - '.part'.length) : name);
      if (chapterId == null) continue;
      final prior = found[chapterId];
      found[chapterId] = (
        mangaId: mangaId,
        hasFinal: (prior?.hasFinal ?? false) || !staging,
        hasStaging: (prior?.hasStaging ?? false) || staging,
      );
    }
  }
  return [
    for (final e in found.entries)
      (
        mangaId: e.value.mangaId,
        chapterId: e.key,
        hasFinal: e.value.hasFinal,
        hasStaging: e.value.hasStaging,
      ),
  ];
}
