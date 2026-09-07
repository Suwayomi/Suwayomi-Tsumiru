import '../offline_database.dart';
import '../offline_page_store.dart';
import '../offline_page_store_io.dart';
import 'background_completion_log.dart';
import 'catchup_work_spec.dart';

typedef QueuedAttempt = ({int bytes, bool transient});
typedef QueuedRunResult = ({
  CatchupLedger ledger,
  int completed,
  bool interrupted,
});

Future<bool> queuedFilesComplete(
  IoOfflinePageStore store,
  QueuedChapterSpec chapter,
) async {
  final committed = await store.inspectCommitted(
    chapter.mangaId,
    chapter.chapterId,
  );
  if (committed.state == ChapterDirState.complete &&
      committed.generation == chapter.generation) {
    return true;
  }
  final manifest = await store.readManifest(chapter.mangaId, chapter.chapterId);
  if (manifest == null ||
      manifest.generation != chapter.generation ||
      manifest.indices.isEmpty) {
    return false;
  }
  final indices = await store.stagedPageIndices(
    chapter.mangaId,
    chapter.chapterId,
  );
  return manifest.indices.every(indices.contains);
}

ChapterEntry? queuedTerminal(
  List<LogEntry> entries,
  QueuedChapterSpec chapter,
) {
  ChapterEntry? terminal;
  var generation = -1;
  for (final entry in entries) {
    if (entry is DeletedEntry &&
        entry.chapterId == chapter.chapterId &&
        entry.generation >= generation) {
      generation = entry.generation;
      terminal = null;
    }
    if (entry is ChapterEntry &&
        entry.chapterId == chapter.chapterId &&
        entry.generation >= generation) {
      generation = entry.generation;
      terminal = entry;
    }
  }
  return generation == chapter.generation ? terminal : null;
}

Future<QueuedRunResult> runQueuedDownloads({
  required CatchupWorkSpec spec,
  required CatchupLedger ledger,
  required IoOfflinePageStore store,
  required BackgroundCompletionLog log,
  required Future<List<OfflineChapter>?> Function(int mangaId) fetchChapters,
  required Future<bool> Function(int chapterId) enqueueServer,
  required Future<QueuedAttempt> Function(
    OfflineChapter row,
    QueuedChapterSpec chapter,
  )
  download,
  required Future<bool> Function(QueuedChapterSpec chapter) shouldStop,
  required Future<bool> Function() capBlocked,
  required Future<void> Function(CatchupLedger ledger) persist,
  int allowance = 10,
}) async {
  var current = ledger;
  var completed = 0;
  final entries = [...await log.parse()];
  final chaptersByManga = <int, List<OfflineChapter>>{};
  final queue = [...spec.queuedChapters]
    ..sort((a, b) {
      final manga = a.mangaId.compareTo(b.mangaId);
      return manga == 0 ? a.chapterId.compareTo(b.chapterId) : manga;
    });
  final seen = <String>{};
  Future<void> terminal(
    QueuedChapterSpec chapter,
    String status, {
    int bytes = 0,
  }) async {
    final manifest = await store.readManifest(
      chapter.mangaId,
      chapter.chapterId,
    );
    final entry = ChapterEntry(
      chapter.chapterId,
      status,
      manifest?.pageCount ?? 0,
      bytes,
      chapter.generation,
    );
    await log.appendChapter(
      chapterId: entry.chapterId,
      status: status,
      pages: entry.pages,
      bytes: bytes,
      generation: chapter.generation,
    );
    entries.add(entry);
  }

  for (final chapter in queue) {
    if (!seen.add(chapter.key)) continue;
    if (await shouldStop(chapter)) {
      return (ledger: current, completed: completed, interrupted: true);
    }
    final prior = queuedTerminal(entries, chapter);
    if (prior?.status == 'error') continue;
    if (await queuedFilesComplete(store, chapter)) {
      if (prior?.status != 'downloaded') {
        await terminal(
          chapter,
          'downloaded',
          bytes: await store.stagedBytes(chapter.mangaId, chapter.chapterId),
        );
      }
      continue;
    }
    if (completed >= allowance) break;
    if (await capBlocked()) {
      final partial = await store.readManifest(
        chapter.mangaId,
        chapter.chapterId,
      );
      if (partial?.generation != chapter.generation ||
          await store.stagedBytes(chapter.mangaId, chapter.chapterId) == 0) {
        continue;
      }
    }
    var rows = chaptersByManga[chapter.mangaId];
    if (rows == null) {
      rows = await fetchChapters(chapter.mangaId);
      if (rows == null) {
        return (ledger: current, completed: completed, interrupted: true);
      }
      chaptersByManga[chapter.mangaId] = rows;
    }
    if (await shouldStop(chapter)) {
      return (ledger: current, completed: completed, interrupted: true);
    }
    final row = rows.where((row) => row.id == chapter.chapterId).firstOrNull;
    final serverSpent = current.queuedServerRetries[chapter.key] ?? 0;
    final deviceSpent = current.queuedDownloadRetries[chapter.key] ?? 0;
    if (row != null && !row.serverIsDownloaded) {
      if (serverSpent >= 5) {
        await terminal(chapter, 'error');
        continue;
      }
      if (!await enqueueServer(chapter.chapterId)) {
        return (ledger: current, completed: completed, interrupted: true);
      }
      if (await shouldStop(chapter)) {
        return (ledger: current, completed: completed, interrupted: true);
      }
      current = current.copyWith(
        queuedServerRetries: {
          ...current.queuedServerRetries,
          chapter.key: serverSpent + 1,
        },
      );
      await persist(current);
      continue;
    }
    if (deviceSpent >= 5) {
      await terminal(chapter, 'error');
      continue;
    }
    final attempt = row == null
        ? (bytes: 0, transient: false)
        : await download(row, chapter);
    if (await shouldStop(chapter)) {
      return (ledger: current, completed: completed, interrupted: true);
    }
    if (attempt.bytes > 0 && await queuedFilesComplete(store, chapter)) {
      await terminal(chapter, 'downloaded', bytes: attempt.bytes);
      completed++;
    } else if (attempt.transient) {
      return (ledger: current, completed: completed, interrupted: true);
    } else {
      current = current.copyWith(
        queuedDownloadRetries: {
          ...current.queuedDownloadRetries,
          chapter.key: deviceSpent + 1,
        },
      );
      await persist(current);
      if (deviceSpent + 1 >= 5) await terminal(chapter, 'error');
    }
  }
  await persist(current);
  return (ledger: current, completed: completed, interrupted: false);
}
