// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';

part 'offline_database.g.dart';

/// On-device state of a chapter's bytes.
enum OfflineDeviceState { none, queued, downloading, downloaded, error, orphaned }

/// How many of a series' chapters to keep on this device automatically.
enum OfflineKeepRule { off, nUnread, allUnread, all }

/// Library manga mirrored for offline browsing. Keyed by the server's stable
/// manga id.
class OfflineMangas extends Table {
  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get thumbnailRelPath => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get keepRule =>
      textEnum<OfflineKeepRule>().withDefault(Constant(OfflineKeepRule.off.name))();
  IntColumn get keepUnreadCount => integer().withDefault(const Constant(3))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Chapter metadata + per-chapter device-download state. Keyed by the server's
/// stable chapter id (NEVER chapterIndex/sourceOrder, which renumbers).
///
/// No FK to [OfflineMangas] by design: the server is canonical, and a chapter
/// whose manga/chapter disappears server-side is reconciled in app logic via
/// [OfflineDeviceState.orphaned] rather than cascade-deleted; `orphaned` is a
/// transient reconciliation marker — server-gone chapters are evicted on the
/// next reconcile pass, not kept indefinitely for explicit cleanup.
@TableIndex(name: 'idx_offline_chapter_manga', columns: {#mangaId})
class OfflineChapters extends Table {
  IntColumn get id => integer()();
  IntColumn get mangaId => integer()();
  TextColumn get name => text()();
  // The server's per-manga ordinal (sourceOrder). Stored for display/order only;
  // never used as a stable key.
  IntColumn get chapterIndex => integer()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  IntColumn get lastPageRead => integer().withDefault(const Constant(0))();
  BoolColumn get isBookmarked => boolean().withDefault(const Constant(false))();
  BoolColumn get serverIsDownloaded =>
      boolean().withDefault(const Constant(false))();
  TextColumn get deviceState => textEnum<OfflineDeviceState>()
      .withDefault(Constant(OfflineDeviceState.none.name))();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get downloadedAt => dateTime().nullable()();

  /// True when this chapter's read progress was updated locally (e.g. read
  /// offline) but not yet pushed to the server. Up-synced on reconnect.
  BoolColumn get progressDirty =>
      boolean().withDefault(const Constant(false))();

  /// True when this chapter's bookmark was toggled locally but not yet pushed
  /// to the server. Tracked separately from [progressDirty] so a read-progress
  /// sync can't clobber a server bookmark that hasn't down-synced yet, and a
  /// bookmark sync can't clobber un-synced read progress (#13/#33).
  BoolColumn get bookmarkDirty =>
      boolean().withDefault(const Constant(false))();

  /// The server's last-read timestamp (epoch millis as a string, matching the
  /// server's LongString) — synced down so the offline library can sort by
  /// "Last Read". Server is the source of truth; this is never the device clock.
  TextColumn get lastReadAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class OfflineCategories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_offline_manga_category_cat', columns: {#categoryId})
class OfflineMangaCategories extends Table {
  IntColumn get mangaId => integer()();
  IntColumn get categoryId => integer()();

  @override
  Set<Column> get primaryKey => {mangaId, categoryId};
}

/// One page of a downloaded chapter → its relative file path under the offline
/// base dir. Page order is the index returned by fetchChapterPages.
class OfflinePages extends Table {
  IntColumn get chapterId => integer()();
  IntColumn get pageIndex => integer()();
  TextColumn get relativePath => text()();

  @override
  Set<Column> get primaryKey => {chapterId, pageIndex};
}

@DriftDatabase(
  tables: [
    OfflineMangas,
    OfflineChapters,
    OfflineCategories,
    OfflineMangaCategories,
    OfflinePages,
  ],
)
class OfflineDatabase extends _$OfflineDatabase {
  OfflineDatabase(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(offlineMangas, offlineMangas.keepRule);
            await m.addColumn(offlineMangas, offlineMangas.keepUnreadCount);
            await m.addColumn(offlineChapters, offlineChapters.pinned);
            await m.addColumn(offlineChapters, offlineChapters.downloadedAt);
          }
          if (from < 3) {
            await m.addColumn(offlineChapters, offlineChapters.progressDirty);
          }
          if (from < 4) {
            await m.addColumn(offlineChapters, offlineChapters.lastReadAt);
          }
          if (from < 5) {
            await m.addColumn(offlineChapters, offlineChapters.bookmarkDirty);
          }
        },
      );

  // --- metadata down-sync upserts -------------------------------------------
  // These set ONLY server-sourced columns, so device-managed columns
  // (deviceState, bytes, thumbnailRelPath) are preserved on conflict and never
  // clobbered by a metadata refresh.

  Future<void> upsertMangaMetadata({
    required int id,
    required String title,
    String? thumbnailUrl,
    required DateTime updatedAt,
  }) =>
      into(offlineMangas).insertOnConflictUpdate(
        OfflineMangasCompanion(
          id: Value(id),
          title: Value(title),
          updatedAt: Value(updatedAt),
          // Don't write NULL over a good URL on a partial refresh; absent when
          // the caller has no URL. thumbnailRelPath stays absent (device-managed).
          thumbnailUrl: thumbnailUrl == null
              ? const Value.absent()
              : Value(thumbnailUrl),
        ),
      );

  Future<void> upsertChapterMetadata({
    required int id,
    required int mangaId,
    required String name,
    required int chapterIndex,
    required bool isRead,
    required int lastPageRead,
    required bool isBookmarked,
    required bool serverIsDownloaded,
    required int pageCount,
    required DateTime updatedAt,
    String? lastReadAt,
  }) =>
      into(offlineChapters).insertOnConflictUpdate(
        OfflineChaptersCompanion(
          id: Value(id),
          mangaId: Value(mangaId),
          name: Value(name),
          chapterIndex: Value(chapterIndex),
          isRead: Value(isRead),
          lastPageRead: Value(lastPageRead),
          isBookmarked: Value(isBookmarked),
          serverIsDownloaded: Value(serverIsDownloaded),
          pageCount: Value(pageCount),
          updatedAt: Value(updatedAt),
          // lastReadAt is server-managed: always take the server's value on
          // re-sync (absent only when an older caller doesn't supply it).
          lastReadAt:
              lastReadAt == null ? const Value.absent() : Value(lastReadAt),
          // deviceState + bytes intentionally absent — device-managed.
        ),
      );

  Future<void> upsertCategory(int id, String name, int sortOrder) =>
      into(offlineCategories).insertOnConflictUpdate(
        OfflineCategoriesCompanion(
          id: Value(id),
          name: Value(name),
          sortOrder: Value(sortOrder),
        ),
      );

  // --- device-managed mutations ---------------------------------------------

  Future<void> setMangaCoverPath(int mangaId, String relPath) =>
      (update(offlineMangas)..where((t) => t.id.equals(mangaId)))
          .write(OfflineMangasCompanion(thumbnailRelPath: Value(relPath)));

  Future<void> setKeepRule(int mangaId, OfflineKeepRule rule, int count) =>
      (update(offlineMangas)..where((t) => t.id.equals(mangaId))).write(
        OfflineMangasCompanion(
          keepRule: Value(rule),
          keepUnreadCount: Value(count),
        ),
      );

  Future<void> setChapterPinned(int chapterId, bool pinned) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId)))
          .write(OfflineChaptersCompanion(pinned: Value(pinned)));

  /// Set a chapter's resolved page count (used to drive the determinate
  /// download progress arc for chapters whose total wasn't known until the
  /// downloader resolved their pages — e.g. webtoon chapters).
  Future<void> setChapterPageCount(int chapterId, int pageCount) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId)))
          .write(OfflineChaptersCompanion(pageCount: Value(pageCount)));

  Future<void> setChapterDeviceState(
    int chapterId,
    OfflineDeviceState state, {
    int? bytes,
    DateTime? downloadedAt,
  }) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          deviceState: Value(state),
          bytes: bytes == null ? const Value.absent() : Value(bytes),
          downloadedAt:
              downloadedAt == null ? const Value.absent() : Value(downloadedAt),
        ),
      );

  /// Record local reading progress (read offline / always). Marks it
  /// `progressDirty` so it's pushed to the server on the next online sync.
  Future<void> setChapterProgress(
    int chapterId, {
    required int lastPageRead,
    required bool isRead,
  }) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          lastPageRead: Value(lastPageRead),
          isRead: Value(isRead),
          progressDirty: const Value(true),
        ),
      );

  /// Clear the progress dirty flag after the progress was pushed to the server.
  Future<void> clearProgressDirty(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId)))
          .write(const OfflineChaptersCompanion(progressDirty: Value(false)));

  /// Clear the bookmark dirty flag after the bookmark was pushed to the server.
  Future<void> clearBookmarkDirty(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId)))
          .write(const OfflineChaptersCompanion(bookmarkDirty: Value(false)));

  /// Clear progressDirty only if the row still holds the exact values that were
  /// pushed — so a newer local write that landed during the push isn't marked
  /// clean and lost (the snapshot-then-clear race). A non-matching row keeps its
  /// flag and re-syncs on the next pass.
  Future<void> clearProgressDirtyIfUnchanged(int chapterId,
          {required int lastPageRead, required bool isRead}) =>
      (update(offlineChapters)
            ..where((t) =>
                t.id.equals(chapterId) &
                t.lastPageRead.equals(lastPageRead) &
                t.isRead.equals(isRead)))
          .write(const OfflineChaptersCompanion(progressDirty: Value(false)));

  /// Clear bookmarkDirty only if the bookmark still matches what was pushed —
  /// same race guard as [clearProgressDirtyIfUnchanged].
  Future<void> clearBookmarkDirtyIfUnchanged(int chapterId,
          {required bool isBookmarked}) =>
      (update(offlineChapters)
            ..where((t) =>
                t.id.equals(chapterId) & t.isBookmarked.equals(isBookmarked)))
          .write(const OfflineChaptersCompanion(bookmarkDirty: Value(false)));

  /// Record a local bookmark change. Marks `bookmarkDirty` (separate from
  /// `progressDirty`) so the bookmark is pushed on the next online sync without
  /// dragging stale read progress with it, and vice versa (#13/#33).
  Future<void> setChapterBookmark(int chapterId, bool isBookmarked) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          isBookmarked: Value(isBookmarked),
          bookmarkDirty: const Value(true),
        ),
      );

  /// Chapters whose local read progress hasn't been pushed to the server.
  Future<List<OfflineChapter>> dirtyProgressChapters() =>
      (select(offlineChapters)..where((t) => t.progressDirty.equals(true)))
          .get();

  /// Chapters with any unpushed local change — read progress OR bookmark — for
  /// the up-sync to flush and the down-sync to preserve.
  Future<List<OfflineChapter>> dirtyChapters() => (select(offlineChapters)
        ..where((t) =>
            t.progressDirty.equals(true) | t.bookmarkDirty.equals(true)))
      .get();

  // --- offline queries -------------------------------------------------------

  Future<OfflineManga?> mangaById(int mangaId) =>
      (select(offlineMangas)..where((t) => t.id.equals(mangaId)))
          .getSingleOrNull();

  Future<OfflineChapter?> chapterById(int chapterId) =>
      (select(offlineChapters)..where((t) => t.id.equals(chapterId)))
          .getSingleOrNull();

  Future<List<OfflineManga>> libraryManga() =>
      (select(offlineMangas)..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .get();

  /// Most-recent read timestamp per manga (the max chapter `lastReadAt`), for
  /// the offline library's "Last Read" sort. Mangas with no read chapter are
  /// absent from the map. Values are the server's epoch-millis strings, so the
  /// max is taken numerically to match how the sort parses them.
  Future<Map<int, String>> lastReadAtByManga() async {
    final maxExpr = offlineChapters.lastReadAt.cast<int>().max();
    final query = selectOnly(offlineChapters)
      ..addColumns([offlineChapters.mangaId, maxExpr])
      ..where(offlineChapters.lastReadAt.isNotNull())
      ..groupBy([offlineChapters.mangaId]);
    final result = <int, String>{};
    for (final row in await query.get()) {
      final mangaId = row.read(offlineChapters.mangaId);
      final value = row.read(maxExpr);
      if (mangaId != null && value != null && value > 0) {
        result[mangaId] = '$value';
      }
    }
    return result;
  }

  /// The next unread chapter that is downloaded on this device, per manga — the
  /// lowest `chapterIndex` row with `isRead = false` and
  /// `deviceState = downloaded`. Drives the offline "continue reading" button:
  /// offline you can only open a chapter that's actually on the device, so a
  /// manga with no downloaded unread chapter is simply absent from the map.
  Future<Map<int, OfflineChapter>> firstUnreadDownloadedChapterByManga() async {
    final rows = await (select(offlineChapters)
          ..where((t) =>
              t.isRead.equals(false) &
              t.deviceState.equalsValue(OfflineDeviceState.downloaded))
          ..orderBy([
            (t) => OrderingTerm(expression: t.mangaId),
            (t) => OrderingTerm(expression: t.chapterIndex),
          ]))
        .get();
    final result = <int, OfflineChapter>{};
    for (final c in rows) {
      // Rows are ordered by chapterIndex, so the first seen per manga is the
      // earliest unread downloaded chapter.
      result.putIfAbsent(c.mangaId, () => c);
    }
    return result;
  }

  Future<List<OfflineChapter>> chaptersForManga(int mangaId) =>
      (select(offlineChapters)
            ..where((t) => t.mangaId.equals(mangaId))
            ..orderBy([(t) => OrderingTerm(expression: t.chapterIndex)]))
          .get();

  /// Mark chapters as orphaned (server-gone) so the next reconcile pass evicts
  /// their on-device copies — keeping the device set a subset of the server.
  Future<void> markChaptersOrphaned(List<int> chapterIds) =>
      (update(offlineChapters)..where((t) => t.id.isIn(chapterIds))).write(
        const OfflineChaptersCompanion(
          deviceState: Value(OfflineDeviceState.orphaned),
        ),
      );

  /// Live stream of a manga's chapter rows — drives the series download
  /// progress UI (emits as device states change during a background download).
  Stream<List<OfflineChapter>> watchChaptersForManga(int mangaId) =>
      (select(offlineChapters)..where((t) => t.mangaId.equals(mangaId))).watch();

  /// Live stream of every chapter that's downloaded OR actively
  /// downloading/queued on this device — drives the Downloads → Offline files
  /// tab (so it shows in-progress downloads, not just finished ones).
  Stream<List<OfflineChapter>> watchOfflineChapters() => (select(offlineChapters)
        ..where((t) => t.deviceState.isIn([
              OfflineDeviceState.downloaded.name,
              OfflineDeviceState.downloading.name,
              OfflineDeviceState.queued.name,
            ])))
      .watch();

  /// Live list of every series with an offline footprint on this device —
  /// either chapters present (downloaded / in-flight) OR an active keep-rule
  /// (`keepRule != off`) — with per-series aggregates and the manga row (which
  /// carries `keepRule` / `keepUnreadCount`). The union is what makes the
  /// Downloads → On device tab the single surface: a rule with nothing
  /// downloaded yet still appears, and hand-saved chapters with no rule still
  /// appear. Updates on either table changing.
  Stream<List<({OfflineManga manga, int downloaded, int inFlight, int bytes})>>
      watchOfflineSeries() {
    final downloaded = offlineChapters.id.count(
        filter:
            offlineChapters.deviceState.equalsValue(OfflineDeviceState.downloaded));
    final inFlight = offlineChapters.id.count(
        filter: offlineChapters.deviceState
                .equalsValue(OfflineDeviceState.downloading) |
            offlineChapters.deviceState.equalsValue(OfflineDeviceState.queued));
    final byteSum = offlineChapters.bytes.sum(
        filter:
            offlineChapters.deviceState.equalsValue(OfflineDeviceState.downloaded));
    final query = select(offlineMangas).join([
      leftOuterJoin(offlineChapters,
          offlineChapters.mangaId.equalsExp(offlineMangas.id)),
    ])
      ..addColumns([downloaded, inFlight, byteSum])
      ..groupBy(
        [offlineMangas.id],
        // Keep series that have files OR a rule; drop the rest of the library.
        having: downloaded.isBiggerThanValue(0) |
            inFlight.isBiggerThanValue(0) |
            offlineMangas.keepRule.equalsValue(OfflineKeepRule.off).not(),
      );
    return query.watch().map((rows) => [
          for (final row in rows)
            (
              manga: row.readTable(offlineMangas),
              downloaded: row.read(downloaded) ?? 0,
              inFlight: row.read(inFlight) ?? 0,
              bytes: row.read(byteSum) ?? 0,
            ),
        ]);
  }

  /// How many pages of a chapter are already on disk. Cheap COUNT (no row
  /// materialisation) — called on the main isolate on every page completion.
  Future<int> downloadedPageCount(int chapterId) async {
    final cnt = offlinePages.pageIndex.count();
    final row = await (selectOnly(offlinePages)
          ..addColumns([cnt])
          ..where(offlinePages.chapterId.equals(chapterId)))
        .getSingle();
    return row.read(cnt) ?? 0;
  }

  /// All chapters currently in a given device state (e.g. queued / downloading),
  /// ordered by manga then chapter — drives the sequential download pump.
  Future<List<OfflineChapter>> chaptersInState(OfflineDeviceState state) =>
      (select(offlineChapters)
            ..where((t) => t.deviceState.equalsValue(state))
            ..orderBy([
              (t) => OrderingTerm(expression: t.mangaId),
              (t) => OrderingTerm(expression: t.chapterIndex),
            ]))
          .get();

  /// The next chapter waiting in the queue (oldest by manga/chapter order), or
  /// null if the queue is empty.
  Future<OfflineChapter?> nextQueuedChapter() => (select(offlineChapters)
        ..where((t) => t.deviceState.equalsValue(OfflineDeviceState.queued))
        ..orderBy([
          (t) => OrderingTerm(expression: t.mangaId),
          (t) => OrderingTerm(expression: t.chapterIndex),
        ])
        ..limit(1))
      .getSingleOrNull();

  Future<List<OfflineChapter>> downloadedChaptersForManga(int mangaId) =>
      (select(offlineChapters)
            ..where((t) =>
                t.mangaId.equals(mangaId) &
                t.deviceState.equalsValue(OfflineDeviceState.downloaded)))
          .get();

  /// Manga ids that have at least one chapter with [OfflineDeviceState.downloaded]
  /// on this device — used by the "On device" library filter.
  Future<Set<int>> mangaIdsWithDeviceDownloads() async {
    final rows = await (selectOnly(offlineChapters, distinct: true)
          ..addColumns([offlineChapters.mangaId])
          ..where(offlineChapters.deviceState
              .equalsValue(OfflineDeviceState.downloaded)))
        .get();
    return {for (final r in rows) r.read(offlineChapters.mangaId)!};
  }

  /// Total bytes used by downloaded chapters — for the storage UI, without a
  /// filesystem walk.
  Future<int> totalDownloadedBytes() async {
    final sum = offlineChapters.bytes.sum();
    final row = await (selectOnly(offlineChapters)
          ..addColumns([sum])
          ..where(offlineChapters.deviceState
              .equalsValue(OfflineDeviceState.downloaded)))
        .getSingle();
    return row.read(sum) ?? 0;
  }
}
