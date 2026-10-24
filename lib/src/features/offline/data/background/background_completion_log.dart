// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import '../chapter_commit.dart';
import '../offline_database.dart';
import '../offline_page_store.dart';

sealed class LogEntry {
  const LogEntry();
}

class ChapterEntry extends LogEntry {
  const ChapterEntry(
    this.chapterId,
    this.status,
    this.pages,
    this.bytes,
    this.generation,
  );
  final int chapterId, pages, bytes, generation;
  final String status; // downloaded | error | authFailed | offline
}

/// Post-delete generation rejects older events even if appended after the tombstone.
class DeletedEntry extends LogEntry {
  const DeletedEntry(this.chapterId, this.generation);
  final int chapterId, generation;
}

class TimeoutEntry extends LogEntry {
  const TimeoutEntry();
}

class DrainedEntry extends LogEntry {
  const DrainedEntry();
}

/// Creates missing rows only for matching server identity and an active keep-rule.
/// Deleted rows remain none and must never be resurrected.
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
    this.status,
    this.generation = 0,
  });
  final int chapterId, mangaId, chapterIndex, pageCount, bytes;
  final String serverId, name;
  final double chapterNumber;
  final bool isRead;
  final String? status;
  final int generation;
}

/// Append-only terminal, adoption, and tombstone records; parse discards a torn final line.
class BackgroundCompletionLog {
  BackgroundCompletionLog(this.file);
  final File file;

  Future<void> _append(Map<String, Object?> obj) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(obj)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> appendChapter({
    required int chapterId,
    required String status,
    required int pages,
    required int bytes,
    int generation = 0,
  }) => _append({
    't': 'chapter',
    'c': chapterId,
    's': status,
    'pages': pages,
    'bytes': bytes,
    'g': generation,
  });

  Future<void> appendDeleted(int chapterId, int generation) =>
      _append({'t': 'deleted', 'c': chapterId, 'g': generation});

  Future<void> appendTimeout() => _append({'t': 'timeout'});

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
    if (e.status != null) 's': e.status,
    'g': e.generation,
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
        // Ignore legacy page records; recovery inspects the filesystem.
        case 'chapter':
          out.add(
            ChapterEntry(
              j['c'] as int,
              j['s'] as String,
              j['pages'] as int,
              j['bytes'] as int,
              j['g'] as int? ?? 0,
            ),
          );
        case 'deleted':
          out.add(DeletedEntry(j['c'] as int, j['g'] as int? ?? 0));
        case 'timeout':
          out.add(const TimeoutEntry());
        case 'drained':
          out.add(const DrainedEntry());
        case 'adopt':
          out.add(
            AdoptChapterEntry(
              chapterId: j['c'] as int,
              mangaId: j['m'] as int,
              serverId: j['srv'] as String? ?? '',
              name: j['n'] as String? ?? '',
              chapterIndex: (j['idx'] as num?)?.toInt() ?? 0,
              chapterNumber: (j['num'] as num?)?.toDouble() ?? -1,
              pageCount: (j['pages'] as num?)?.toInt() ?? 0,
              bytes: (j['bytes'] as num?)?.toInt() ?? 0,
              isRead: j['read'] as bool? ?? false,
              status: j['s'] as String?,
              generation: j['g'] as int? ?? 0,
            ),
          );
      }
    }
    return out;
  }

  Future<void> truncate() async {
    if (await file.exists()) await file.writeAsString('', flush: true);
  }
}

/// Applies failures only; success requires commit. Rejects events older than downloadGeneration.
Future<void> applyBackgroundTerminalState({
  required OfflineDatabase db,
  required int chapterId,
  required String status,
  int eventGeneration = 0,
}) async {
  if (status != 'error' && status != 'permissionDenied') {
    return;
  }
  await db.transaction(() async {
    final c = await db.chapterById(chapterId);
    if (c == null || c.deviceState == OfflineDeviceState.none) return;
    if (eventGeneration != c.downloadGeneration) return; // stale generation
    // chapterStart and terminal events are unawaited; a fast failure can arrive while still queued.
    if (c.deviceState == OfflineDeviceState.downloading ||
        c.deviceState == OfflineDeviceState.queued) {
      await db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
    }
  });
}

/// Recovers files against catalog state before replaying worker records.
Future<void> replayCompletionLog({
  required OfflineDatabase db,
  required OfflinePageStore store,
  required BackgroundCompletionLog log,
  String? catalogServerId,
  Future<void> Function()? onTimeout,
}) async {
  final entries = await log.parse();

  // Create adoption rows before recovery can treat their files as unauthorized orphans.
  await _adoptCatchupChapters(
    db: db,
    store: store,
    entries: entries,
    catalogServerId: catalogServerId,
  );

  await recoverChaptersOnDisk(db: db, store: store);

  await _applyTerminalEntries(db: db, entries: entries);

  if (entries.any((entry) => entry is TimeoutEntry)) await onTimeout?.call();
  await log.truncate();
}

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
    final existing = await db.chapterById(a.chapterId);
    final failed = a.status == 'permissionDenied' || a.status == 'error';
    if (a.generation != 0) continue;
    if (entries.whereType<DeletedEntry>().any(
      (e) => e.chapterId == a.chapterId && e.generation >= a.generation,
    )) {
      continue;
    }
    if (existing != null &&
        !(existing.mangaId == a.mangaId &&
            existing.deviceState == OfflineDeviceState.none &&
            existing.downloadGeneration == 0 &&
            a.generation == 0)) {
      continue;
    }
    final manga = await (db.select(
      db.offlineMangas,
    )..where((t) => t.id.equals(a.mangaId))).getSingleOrNull();
    final accepted =
        manga != null &&
        manga.keepRule != OfflineKeepRule.off &&
        catalogServerId != null &&
        a.serverId == catalogServerId;
    if (!accepted) {
      // Refused adoptions have no row for eviction to find; clean their files under replay ownership.
      if (!failed) await store.deleteChapter(a.mangaId, a.chapterId);
      continue;
    }
    await db.transaction(() async {
      final current = await db.chapterById(a.chapterId);
      if (current != null) {
        if (current.mangaId == a.mangaId &&
            current.deviceState == OfflineDeviceState.none &&
            current.downloadGeneration == 0 &&
            a.generation == 0) {
          await db.setChapterDeviceState(
            a.chapterId,
            failed ? OfflineDeviceState.error : OfflineDeviceState.downloading,
          );
        }
        return;
      }
      await db.upsertChapterMetadata(
        id: a.chapterId,
        mangaId: a.mangaId,
        name: a.name,
        chapterIndex: a.chapterIndex,
        isRead: a.isRead,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: !failed,
        pageCount: a.pageCount,
        updatedAt: DateTime.now(),
        chapterNumber: a.chapterNumber < 0 ? null : a.chapterNumber,
        syncedIsRead: a.isRead,
      );
      // Claim before commit so incomplete files remain resumable.
      await db.setChapterDeviceState(
        a.chapterId,
        failed ? OfflineDeviceState.error : OfflineDeviceState.downloading,
      );
    });
  }
}

// Apply only the newest generation so pre-delete events cannot fail re-queued downloads.
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
      case TimeoutEntry():
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
