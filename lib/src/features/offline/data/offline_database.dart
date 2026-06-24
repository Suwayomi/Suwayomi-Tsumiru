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
  int get schemaVersion => 3;

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

  /// Clear the dirty flag after the progress was pushed to the server.
  Future<void> clearProgressDirty(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId)))
          .write(const OfflineChaptersCompanion(progressDirty: Value(false)));

  /// Chapters whose local read progress hasn't been pushed to the server.
  Future<List<OfflineChapter>> dirtyProgressChapters() =>
      (select(offlineChapters)..where((t) => t.progressDirty.equals(true)))
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

  Future<List<OfflineChapter>> chaptersForManga(int mangaId) =>
      (select(offlineChapters)
            ..where((t) => t.mangaId.equals(mangaId))
            ..orderBy([(t) => OrderingTerm(expression: t.chapterIndex)]))
          .get();

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
