// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import '../offline_database.dart';
import '../offline_paths.dart';

sealed class LogEntry {
  const LogEntry();
}

class PageEntry extends LogEntry {
  const PageEntry(this.chapterId, this.mangaId, this.pageIndex, this.relPath, this.bytes);
  final int chapterId, mangaId, pageIndex, bytes;
  final String relPath;
}

class ChapterEntry extends LogEntry {
  const ChapterEntry(this.chapterId, this.status, this.pages, this.bytes);
  final int chapterId, pages, bytes;
  final String status; // downloaded | error | authFailed | offline
}

class DrainedEntry extends LogEntry {
  const DrainedEntry();
}

/// Append-only JSONL record of background-download progress. The DURABLE source
/// of truth the main isolate replays into drift on resume/launch. One JSON object
/// per line, flushed. A torn final line (process killed mid-write) is silently
/// discarded on parse; page files are independently crash-safe (atomic write).
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
  }) =>
      _append({'t': 'page', 'c': chapterId, 'm': mangaId, 'i': pageIndex, 'p': relPath, 'b': bytes});

  Future<void> appendChapter({
    required int chapterId,
    required String status,
    required int pages,
    required int bytes,
  }) =>
      _append({'t': 'chapter', 'c': chapterId, 's': status, 'pages': pages, 'bytes': bytes});

  Future<void> appendDrained() => _append({'t': 'drained'});

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
          out.add(PageEntry(j['c'] as int, j['m'] as int, j['i'] as int, j['p'] as String, j['b'] as int));
        case 'chapter':
          out.add(ChapterEntry(j['c'] as int, j['s'] as String, j['pages'] as int, j['bytes'] as int));
        case 'drained':
          out.add(const DrainedEntry());
      }
    }
    return out;
  }

  Future<void> truncate() async {
    if (await file.exists()) await file.writeAsString('', flush: true);
  }
}

typedef ChapterBytesMeasurer = Future<int> Function(int mangaId, int chapterId);

Future<void> replayCompletionLog({
  required OfflineDatabase db,
  required OfflinePaths paths,
  required BackgroundCompletionLog log,
  required ChapterBytesMeasurer measureBytes,
}) async {
  final entries = await log.parse();
  if (entries.isEmpty) return;

  // Which chapters were touched + their terminal status (last one wins).
  final touched = <int, int>{}; // chapterId -> mangaId
  final terminal = <int, String>{};
  for (final e in entries) {
    switch (e) {
      case PageEntry(:final chapterId, :final mangaId):
        touched[chapterId] = mangaId;
      case ChapterEntry(:final chapterId, :final status):
        terminal[chapterId] = status;
        // mangaId for a chapter-only entry comes from drift below
      case DrainedEntry():
        break;
    }
  }

  for (final chapterId in {...touched.keys, ...terminal.keys}) {
    final ch = await db.chapterById(chapterId);
    // Skip deleted/cleared chapters — never resurrect (design: filesystem is
    // subordinate to drift authority here).
    if (ch == null || ch.deviceState == OfflineDeviceState.none) continue;
    final mangaId = touched[chapterId] ?? ch.mangaId;

    // Filesystem is truth: upsert a row for every page file on disk.
    final dir = Directory(paths.absolute(paths.chapterDirRel(mangaId, chapterId)));
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last; // e.g. 003.jpg
        final dot = name.indexOf('.');
        if (dot <= 0) continue;
        final idx = int.tryParse(name.substring(0, dot));
        if (idx == null) continue;
        await db.into(db.offlinePages).insertOnConflictUpdate(
              OfflinePagesCompanion.insert(
                chapterId: chapterId,
                pageIndex: idx,
                relativePath: paths.pageRel(mangaId, chapterId, idx,
                    name.substring(dot + 1)),
              ),
            );
      }
    }

    // Apply terminal state.
    switch (terminal[chapterId]) {
      case 'downloaded':
        final bytes = await measureBytes(mangaId, chapterId);
        await db.setChapterDeviceState(chapterId, OfflineDeviceState.downloaded,
            bytes: bytes, downloadedAt: DateTime.now());
      case 'error':
      case 'authFailed':
        await db.setChapterDeviceState(chapterId, OfflineDeviceState.error);
      case 'offline':
      case null:
        // leave downloading — resumed later by the pump/worker
        break;
    }
  }

  await log.truncate();
}
