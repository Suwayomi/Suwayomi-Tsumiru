// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import '../offline_database.dart';
import '../offline_paths.dart';
import '../offline_types.dart';

/// Final on-disk pages of a chapter, index → relative path. `.part` staging
/// files are excluded as incomplete.
Future<Map<int, String>> _pagesOnDisk(
    OfflinePaths paths, int mangaId, int chapterId) async {
  final rowsByIndex = <int, String>{};
  final dir = Directory(paths.absolute(paths.chapterDirRel(mangaId, chapterId)));
  if (await dir.exists()) {
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.part')) continue;
      final dot = name.indexOf('.');
      if (dot <= 0) continue;
      final idx = int.tryParse(name.substring(0, dot));
      if (idx == null) continue;
      rowsByIndex[idx] =
          paths.pageRel(mangaId, chapterId, idx, name.substring(dot + 1));
    }
  }
  return rowsByIndex;
}

sealed class LogEntry {
  const LogEntry();
}

class PageEntry extends LogEntry {
  const PageEntry(this.chapterId, this.mangaId, this.pageIndex, this.relPath,
      this.bytes, this.generation);
  final int chapterId, mangaId, pageIndex, bytes, generation;
  final String relPath;
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
/// source of truth replayed into drift on resume/launch. A torn final line
/// (killed mid-write) is silently discarded on parse.
class BackgroundCompletionLog {
  BackgroundCompletionLog(this.file);
  final File file;

  Future<void> _append(Map<String, Object?> obj) async {
    await file.parent.create(recursive: true);
    await file.writeAsString('${jsonEncode(obj)}\n',
        mode: FileMode.append, flush: true);
  }

  Future<void> appendPage({
    required int chapterId,
    required int mangaId,
    required int pageIndex,
    required String relPath,
    required int bytes,
    int generation = 0,
  }) =>
      _append({'t': 'page', 'c': chapterId, 'm': mangaId, 'i': pageIndex, 'p': relPath, 'b': bytes, 'g': generation});

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
        case 'page':
          out.add(PageEntry(j['c'] as int, j['m'] as int, j['i'] as int, j['p'] as String, j['b'] as int, j['g'] as int? ?? 0));
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

typedef ChapterBytesMeasurer = Future<int> Function(int mangaId, int chapterId);

/// Apply a worker terminal event (chapterDone) to drift. `downloaded` is
/// verified against page rows actually on disk, and [eventGeneration] older
/// than the chapter's persisted `downloadGeneration` (bumped on each delete) is
/// dropped — both guard against a stale event from a deleted/re-queued chapter.
Future<void> applyBackgroundTerminalState({
  required OfflineDatabase db,
  required int chapterId,
  required String status,
  required int bytes,
  int eventGeneration = 0,
}) async {
  await db.transaction(() async {
    final c = await db.chapterById(chapterId);
    if (c == null || c.deviceState == OfflineDeviceState.none) return;
    if (eventGeneration < c.downloadGeneration) return; // stale generation
    switch (status) {
      case 'downloaded':
        final pages = await db.downloadedPageCount(chapterId);
        if (pages <= 0 || (c.pageCount > 0 && pages < c.pageCount)) return;
        await db.setChapterDeviceState(chapterId, OfflineDeviceState.downloaded,
            bytes: bytes, downloadedAt: DateTime.now());
      case 'error':
      case 'authFailed':
        if (c.deviceState == OfflineDeviceState.downloading) {
          await db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
        }
      // 'offline' / null: leave `downloading` so it resumes.
    }
  });
}

Future<void> replayCompletionLog({
  required OfflineDatabase db,
  required OfflinePaths paths,
  required BackgroundCompletionLog log,
  required ChapterBytesMeasurer measureBytes,
  String? catalogServerId,
}) async {
  final entries = await log.parse();
  if (entries.isEmpty) return;

  // Background catch-up adoptions first: rows drift has never seen. Refusals
  // clean their files up here, under replay's ownership — refused downloads
  // are invisible to eviction (no row) and would otherwise sit on disk forever.
  final adoptions = <int, AdoptChapterEntry>{};
  for (final e in entries) {
    if (e is AdoptChapterEntry) adoptions[e.chapterId] = e;
  }
  for (final a in adoptions.values) {
    if (await db.chapterById(a.chapterId) != null) continue; // known → normal path
    final manga = await (db.select(db.offlineMangas)
          ..where((t) => t.id.equals(a.mangaId)))
        .getSingleOrNull();
    final pagesOnDisk = await _pagesOnDisk(paths, a.mangaId, a.chapterId);
    final complete = a.pageCount > 0 &&
        List.generate(a.pageCount, (i) => i).every(pagesOnDisk.containsKey);
    final accepted = manga != null &&
        manga.keepRule != OfflineKeepRule.off &&
        catalogServerId != null &&
        a.serverId == catalogServerId &&
        complete;
    if (!accepted) {
      try {
        final dir = Directory(
            paths.absolute(paths.chapterDirRel(a.mangaId, a.chapterId)));
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
      continue;
    }
    final bytes = await measureBytes(a.mangaId, a.chapterId);
    await db.transaction(() async {
      if (await db.chapterById(a.chapterId) != null) return; // raced a sync
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
      for (final entry in pagesOnDisk.entries) {
        await db.into(db.offlinePages).insertOnConflictUpdate(
              OfflinePagesCompanion.insert(
                  chapterId: a.chapterId,
                  pageIndex: entry.key,
                  relativePath: entry.value),
            );
      }
      await db.setChapterDeviceState(a.chapterId, OfflineDeviceState.downloaded,
          bytes: bytes, downloadedAt: DateTime.now());
    });
  }

  // touched/terminal are scoped to the latest generation seen per chapter, so a
  // stale entry (even one after the delete in file order) is discarded rather
  // than applied to a re-queued chapter.
  final touched = <int, int>{}; // chapterId -> mangaId
  final terminal = <int, String>{};
  final terminalPages = <int, int>{}; // expected page count from the entry
  final gen = <int, int>{}; // highest generation seen per chapter

  // Advance a chapter to a newer generation, wiping everything accumulated for
  // older ones.
  void advance(int chapterId, int g) {
    if (g > (gen[chapterId] ?? 0)) {
      gen[chapterId] = g;
      touched.remove(chapterId);
      terminal.remove(chapterId);
      terminalPages.remove(chapterId);
    }
  }

  for (final e in entries) {
    switch (e) {
      case PageEntry(:final chapterId, :final mangaId, :final generation):
        advance(chapterId, generation);
        if (generation < (gen[chapterId] ?? 0)) break; // stale generation
        touched[chapterId] = mangaId;
      case ChapterEntry(:final chapterId, :final status, :final pages,
            :final generation):
        advance(chapterId, generation);
        if (generation < (gen[chapterId] ?? 0)) break; // stale generation
        terminal[chapterId] = status;
        terminalPages[chapterId] = pages;
        // mangaId for a chapter-only entry comes from drift below
      case DeletedEntry(:final chapterId, :final generation):
        // Advance to the delete's new generation and wipe prior accumulation; a
        // re-download at that generation re-accumulates on later iterations.
        advance(chapterId, generation);
        touched.remove(chapterId);
        terminal.remove(chapterId);
        terminalPages.remove(chapterId);
      case DrainedEntry():
        break;
      case AdoptChapterEntry():
        break; // handled in the adoption pass above
    }
  }

  for (final chapterId in {...touched.keys, ...terminal.keys}) {
    final ch = await db.chapterById(chapterId);
    // Skip deleted/cleared chapters — never resurrect (design: filesystem is
    // subordinate to drift authority here).
    if (ch == null || ch.deviceState == OfflineDeviceState.none) continue;
    // drift's persisted generation is authority: if it's advanced past
    // everything in the log (e.g. tombstone truncated across a restart), the
    // log is stale for this chapter.
    if ((gen[chapterId] ?? 0) < ch.downloadGeneration) continue;
    final mangaId = touched[chapterId] ?? ch.mangaId;

    // Enumerate final on-disk pages (filesystem is truth) and measure bytes
    // BEFORE the transaction, so the DB write stays atomic and serializes with
    // a delete.
    final rowsByIndex = await _pagesOnDisk(paths, mangaId, chapterId);
    final status = terminal[chapterId];
    final bytes =
        status == 'downloaded' ? await measureBytes(mangaId, chapterId) : 0;

    // Recheck state, then upsert rows + apply terminal state atomically: a
    // delete that commits after the check above must win, not be overwritten.
    await db.transaction(() async {
      final c = await db.chapterById(chapterId);
      if (c == null || c.deviceState == OfflineDeviceState.none) return;
      for (final entry in rowsByIndex.entries) {
        await db.into(db.offlinePages).insertOnConflictUpdate(
              OfflinePagesCompanion.insert(
                  chapterId: chapterId,
                  pageIndex: entry.key,
                  relativePath: entry.value),
            );
      }
      switch (status) {
        case 'downloaded':
          // Verify against files actually on disk, not log metadata: a stale
          // `downloaded` racing a delete/re-queue finds too few pages and must
          // not complete the chapter. Requires the full expected page set, not
          // just a partial.
          final expected = terminalPages[chapterId] ?? 0;
          final complete = expected > 0
              ? List.generate(expected, (i) => i).every(rowsByIndex.containsKey)
              : rowsByIndex.isNotEmpty;
          if (!complete) break;
          await db.setChapterDeviceState(
              chapterId, OfflineDeviceState.downloaded,
              bytes: bytes, downloadedAt: DateTime.now());
        case 'error':
        case 'authFailed':
          await db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
        case 'offline':
        case null:
          break; // leave downloading — resumed later by the pump/worker
      }
    });
  }

  await log.truncate();
}
