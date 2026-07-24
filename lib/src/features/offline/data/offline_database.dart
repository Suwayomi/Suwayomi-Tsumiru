// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';

import 'offline_types.dart';

export 'offline_types.dart';

part 'offline_database.g.dart';

/// Library manga mirrored for offline browsing. Keyed by the server's stable
/// manga id.
class OfflineMangas extends Table {
  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get thumbnailRelPath => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get keepRule => textEnum<OfflineKeepRule>()
      .withDefault(Constant(OfflineKeepRule.off.name))();
  IntColumn get keepUnreadCount => integer().withDefault(const Constant(3))();

  // Server-sourced metadata for offline filters / sort / badges / grouping.
  TextColumn get sourceId => text().nullable()();
  TextColumn get sourceName => text().nullable()();
  TextColumn get sourceLang => text().nullable()();
  BoolColumn get sourceIsNsfw => boolean().withDefault(const Constant(false))();
  TextColumn get status => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get downloadCount => integer().withDefault(const Constant(0))();
  IntColumn get bookmarkCount => integer().withDefault(const Constant(0))();
  TextColumn get inLibraryAt => text().nullable()();
  TextColumn get latestFetchedAt => text().nullable()();
  TextColumn get latestUploadedAt => text().nullable()();
  IntColumn get totalChapters => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Chapter metadata + per-chapter device-download state, keyed by the server's
/// stable chapter id (never chapterIndex/sourceOrder, which renumbers). No FK
/// to [OfflineMangas] by design — a chapter whose manga disappears
/// server-side is reconciled via [OfflineDeviceState.orphaned] and evicted on
/// the next reconcile pass, not cascade-deleted.
@TableIndex(name: 'idx_offline_chapter_manga', columns: {#mangaId})
class OfflineChapters extends Table {
  IntColumn get id => integer()();
  IntColumn get mangaId => integer()();
  TextColumn get name => text()();
  // The server's per-manga ordinal (sourceOrder). Stored for display/order only;
  // never used as a stable key.
  IntColumn get chapterIndex => integer()();
  // Real chapter number + scanlator, synced so the offline list can group
  // scanlator duplicates (#141). Null until the row's next down-sync.
  RealColumn get chapterNumber => real().nullable()();
  TextColumn get scanlator => text().nullable()();
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

  /// True when this chapter's bookmark was toggled locally but not yet pushed.
  /// Tracked separately from [progressDirty] so a read-progress sync can't
  /// clobber an un-synced bookmark, or vice versa (#13/#33).
  BoolColumn get bookmarkDirty =>
      boolean().withDefault(const Constant(false))();

  /// True when this chapter's read-STATE (isRead) changed locally but not yet
  /// pushed — separate from [progressDirty] so a position-only write can't
  /// push a stale isRead (the ch-99 loop), mirroring [bookmarkDirty] (#13).
  BoolColumn get readStateDirty =>
      boolean().withDefault(const Constant(false))();

  /// The server's last-read timestamp (epoch millis as a string) synced down
  /// so the offline library can sort by "Last Read" — server is the source of
  /// truth, never the device clock.
  TextColumn get lastReadAt => text().nullable()();

  /// Monotonic download generation, bumped on every delete and persisted so a
  /// restart can't let a re-queued download reuse one. Background events carry
  /// their starting generation; anything below the current value is dropped so
  /// a stale event can't corrupt a re-queued download.
  IntColumn get downloadGeneration =>
      integer().withDefault(const Constant(0))();

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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Idempotent adds: a device migrated by an intermediate/dev build can
          // already have a column while still recording an older schema version,
          // which would make a plain addColumn crash with "duplicate column".
          if (from < 2) {
            await _addColumnIfMissing(m, offlineMangas, offlineMangas.keepRule);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.keepUnreadCount);
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.pinned);
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.downloadedAt);
          }
          if (from < 3) {
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.progressDirty);
          }
          if (from < 4) {
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.lastReadAt);
          }
          if (from < 5) {
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.bookmarkDirty);
          }
          if (from < 6) {
            await _addColumnIfMissing(m, offlineMangas, offlineMangas.sourceId);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.sourceName);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.sourceLang);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.sourceIsNsfw);
            await _addColumnIfMissing(m, offlineMangas, offlineMangas.status);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.unreadCount);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.downloadCount);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.bookmarkCount);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.inLibraryAt);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.latestFetchedAt);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.latestUploadedAt);
            await _addColumnIfMissing(
                m, offlineMangas, offlineMangas.totalChapters);
          }
          if (from < 7) {
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.readStateDirty);
            // Carry pending reads across the split: a progress-dirty row with
            // isRead=true is usually a completed offline read awaiting push
            // (it may also be a server-sourced true on a partial re-read —
            // pushing true is the safe direction). is_read=0 dirty rows are
            // exactly the stale class; they stay position-only.
            await customStatement(
                'UPDATE offline_chapters SET read_state_dirty = 1 '
                'WHERE progress_dirty = 1 AND is_read = 1');
          }
          if (from < 8) {
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.downloadGeneration);
          }
          if (from < 9) {
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.chapterNumber);
            await _addColumnIfMissing(
                m, offlineChapters, offlineChapters.scanlator);
          }
        },
      );

  /// drift's [Migrator.addColumn] throws if the column already exists — a
  /// device migrated by an intermediate/dev build can have it present at an
  /// older recorded schema version, so guard each add to stay idempotent.
  Future<void> _addColumnIfMissing(
      Migrator m, TableInfo table, GeneratedColumn column) async {
    final info =
        await customSelect("PRAGMA table_info('${table.actualTableName}')")
            .get();
    final exists = info.any((row) => row.read<String>('name') == column.name);
    if (!exists) await m.addColumn(table, column);
  }

  // --- metadata down-sync upserts -------------------------------------------
  // These set ONLY server-sourced columns, so device-managed columns
  // (deviceState, bytes, thumbnailRelPath) survive a metadata refresh untouched.

  Future<void> upsertMangaMetadata({
    required int id,
    required String title,
    String? thumbnailUrl,
    required DateTime updatedAt,
    String? sourceId,
    String? sourceName,
    String? sourceLang,
    bool sourceIsNsfw = false,
    String? status,
    int unreadCount = 0,
    int downloadCount = 0,
    int bookmarkCount = 0,
    String? inLibraryAt,
    String? latestFetchedAt,
    String? latestUploadedAt,
    int totalChapters = 0,
  }) =>
      into(offlineMangas).insertOnConflictUpdate(
        OfflineMangasCompanion(
          id: Value(id),
          title: Value(title),
          updatedAt: Value(updatedAt),
          thumbnailUrl:
              thumbnailUrl == null ? const Value.absent() : Value(thumbnailUrl),
          // device-managed: thumbnailRelPath, keepRule, keepUnreadCount stay absent
          sourceId: Value(sourceId),
          sourceName: Value(sourceName),
          sourceLang: Value(sourceLang),
          sourceIsNsfw: Value(sourceIsNsfw),
          status: Value(status),
          unreadCount: Value(unreadCount),
          downloadCount: Value(downloadCount),
          bookmarkCount: Value(bookmarkCount),
          inLibraryAt: Value(inLibraryAt),
          latestFetchedAt: Value(latestFetchedAt),
          latestUploadedAt: Value(latestUploadedAt),
          totalChapters: Value(totalChapters),
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
    double? chapterNumber,
    String? scanlator,
  }) =>
      into(offlineChapters).insertOnConflictUpdate(
        OfflineChaptersCompanion(
          id: Value(id),
          mangaId: Value(mangaId),
          name: Value(name),
          chapterIndex: Value(chapterIndex),
          chapterNumber: Value(chapterNumber),
          scanlator: Value(scanlator),
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

  /// Replace a manga's full category membership atomically (delete-then-insert).
  /// Safe to call with an empty list — just removes all memberships.
  Future<void> replaceMangaCategories(int mangaId, List<int> categoryIds) =>
      transaction(() async {
        await (delete(offlineMangaCategories)
              ..where((t) => t.mangaId.equals(mangaId)))
            .go();
        for (final catId in categoryIds) {
          await into(offlineMangaCategories).insertOnConflictUpdate(
            OfflineMangaCategoriesCompanion(
              mangaId: Value(mangaId),
              categoryId: Value(catId),
            ),
          );
        }
      });

  /// Categories a manga belongs to (for the offline mapper).
  Future<List<OfflineCategory>> categoriesForManga(int mangaId) async {
    final query = select(offlineCategories).join([
      innerJoin(
        offlineMangaCategories,
        offlineMangaCategories.categoryId.equalsExp(offlineCategories.id) &
            offlineMangaCategories.mangaId.equals(mangaId),
      ),
    ])
      ..orderBy([OrderingTerm(expression: offlineCategories.sortOrder)]);
    return (await query.get())
        .map((row) => row.readTable(offlineCategories))
        .toList();
  }

  /// All persisted categories — for the offline category-list fallback.
  Future<List<OfflineCategory>> allOfflineCategories() =>
      (select(offlineCategories)
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

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

  /// Set a chapter's resolved page count — drives the determinate download
  /// progress arc for chapters (e.g. webtoon) whose total wasn't known until
  /// the downloader resolved their pages.
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

  /// Atomically record a chapter whose page files were transferred from a
  /// migration source: rewrite the target's page rows and mark it downloaded in
  /// ONE transaction, so a crash can't leave files-present-but-not-downloaded (or
  /// vice versa). On a move ([clearSourceChapterId] set) the source row is reset
  /// in the same tx so it's never double-counted.
  Future<void> commitTransferredChapter({
    required int toChapterId,
    required List<({int pageIndex, String relPath, int bytes})> pages,
    required DateTime downloadedAt,
    required bool pinned,
    int? clearSourceChapterId,
  }) =>
      transaction(() async {
        await (delete(offlinePages)
              ..where((t) => t.chapterId.equals(toChapterId)))
            .go();
        for (final pg in pages) {
          await into(offlinePages).insertOnConflictUpdate(
            OfflinePagesCompanion(
              chapterId: Value(toChapterId),
              pageIndex: Value(pg.pageIndex),
              relativePath: Value(pg.relPath),
            ),
          );
        }
        await (update(offlineChapters)..where((t) => t.id.equals(toChapterId)))
            .write(OfflineChaptersCompanion(
          deviceState: const Value(OfflineDeviceState.downloaded),
          bytes: Value(pages.fold<int>(0, (s, p) => s + p.bytes)),
          pageCount: Value(pages.length),
          downloadedAt: Value(downloadedAt),
          pinned: Value(pinned),
        ));
        if (clearSourceChapterId != null) {
          await (delete(offlinePages)
                ..where((t) => t.chapterId.equals(clearSourceChapterId)))
              .go();
          await (update(offlineChapters)
                ..where((t) => t.id.equals(clearSourceChapterId)))
              .write(const OfflineChaptersCompanion(
            deviceState: Value(OfflineDeviceState.none),
            bytes: Value(0),
          ));
        }
      });

  /// Unpin every chapter of a manga — used on Migrate so the source's kept
  /// chapters aren't held back from the post-removal purge reconcile.
  Future<void> unpinChaptersForManga(int mangaId) =>
      (update(offlineChapters)..where((t) => t.mangaId.equals(mangaId)))
          .write(const OfflineChaptersCompanion(pinned: Value(false)));

  /// Bump a chapter's persistent download generation and return the new
  /// value — called on every delete so a re-queued download outranks any
  /// still-in-flight event, and persisted so it survives a restart.
  Future<int> bumpChapterGeneration(int chapterId) => transaction(() async {
        final current = await chapterById(chapterId);
        final next = (current?.downloadGeneration ?? 0) + 1;
        await (update(offlineChapters)..where((t) => t.id.equals(chapterId)))
            .write(OfflineChaptersCompanion(downloadGeneration: Value(next)));
        return next;
      });

  /// Record local reading progress (read offline / always). Marks it
  /// `progressDirty` so it's pushed to the server on the next online sync.
  Future<void> setChapterProgress(
    int chapterId, {
    required int lastPageRead,
    bool? isRead,
  }) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          lastPageRead: Value(lastPageRead),
          progressDirty: const Value(true),
          // null → leave read-state untouched (a partial write must not
          // un-read); a read-state change rides its OWN flag so position-only
          // writes can't push a stale isRead (the ch-99 loop).
          isRead: isRead == null ? const Value.absent() : Value(isRead),
          readStateDirty:
              isRead == null ? const Value.absent() : const Value(true),
        ),
      );

  /// Record a local read/unread change (list actions, mark-read). Position
  /// untouched; pushed under its own flag on the next online sync.
  Future<void> setChapterReadState(int chapterId, bool isRead) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          isRead: Value(isRead),
          readStateDirty: const Value(true),
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

  /// Clear progressDirty only if the row still holds the exact pushed values —
  /// so a newer local write landing mid-push isn't marked clean and lost (the
  /// snapshot-then-clear race); a non-matching row keeps its flag and re-syncs.
  Future<void> clearProgressDirtyIfUnchanged(int chapterId,
          {required int lastPageRead}) =>
      (update(offlineChapters)
            ..where((t) =>
                t.id.equals(chapterId) & t.lastPageRead.equals(lastPageRead)))
          .write(const OfflineChaptersCompanion(progressDirty: Value(false)));

  /// Clear readStateDirty only if the row's isRead still matches what was
  /// pushed — the same race guard as [clearProgressDirtyIfUnchanged], mirroring
  /// [clearBookmarkDirtyIfUnchanged].
  Future<void> clearReadStateDirtyIfUnchanged(int chapterId,
          {required bool isRead}) =>
      (update(offlineChapters)
            ..where((t) => t.id.equals(chapterId) & t.isRead.equals(isRead)))
          .write(const OfflineChaptersCompanion(readStateDirty: Value(false)));

  /// Clear bookmarkDirty only if the bookmark still matches what was pushed —
  /// same race guard as [clearProgressDirtyIfUnchanged].
  Future<void> clearBookmarkDirtyIfUnchanged(int chapterId,
          {required bool isBookmarked}) =>
      (update(offlineChapters)
            ..where((t) =>
                t.id.equals(chapterId) & t.isBookmarked.equals(isBookmarked)))
          .write(const OfflineChaptersCompanion(bookmarkDirty: Value(false)));

  /// Record a local bookmark change, marking `bookmarkDirty` (separate from
  /// `progressDirty`) so the bookmark pushes without dragging stale read
  /// progress along, and vice versa (#13/#33).
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
            t.progressDirty.equals(true) |
            t.bookmarkDirty.equals(true) |
            t.readStateDirty.equals(true)))
      .get();

  // --- offline queries -------------------------------------------------------

  Future<OfflineManga?> mangaById(int mangaId) =>
      (select(offlineMangas)..where((t) => t.id.equals(mangaId)))
          .getSingleOrNull();

  Future<OfflineChapter?> chapterById(int chapterId) =>
      (select(offlineChapters)..where((t) => t.id.equals(chapterId)))
          .getSingleOrNull();

  Future<List<OfflineManga>> libraryManga() => (select(offlineMangas)
        ..orderBy([(t) => OrderingTerm(expression: t.title)]))
      .get();

  Future<bool> hasCatalogData() async =>
      (await (select(offlineMangas)..limit(1)).get()).isNotEmpty;

  Future<void> clearAll() => transaction(() async {
        await delete(offlinePages).go();
        await delete(offlineMangaCategories).go();
        await delete(offlineCategories).go();
        await delete(offlineChapters).go();
        await delete(offlineMangas).go();
      });

  /// Sweep browsed-not-added manga a past bug wrote here: no library timestamp
  /// and nothing downloaded. Never touches downloads — a swept stray row just
  /// re-mirrors on the next online load.
  Future<int> purgeNonLibraryManga() {
    final withDeviceContent = selectOnly(offlineChapters)
      ..addColumns([offlineChapters.mangaId])
      ..where(offlineChapters.deviceState
          .equalsValue(OfflineDeviceState.none)
          .not());
    return (delete(offlineMangas)
          ..where((t) =>
              (t.inLibraryAt.isNull() | t.inLibraryAt.equals('0')) &
              t.id.isNotInQuery(withDeviceContent)))
        .go();
  }

  /// Most-recent read timestamp per manga (max chapter `lastReadAt`), for the
  /// offline library's "Last Read" sort — absent for mangas with no read
  /// chapter. Values are epoch-millis strings, so the max is taken numerically.
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

  /// The next unread downloaded chapter per manga (lowest `chapterIndex` with
  /// `isRead = false` and `deviceState = downloaded`) — drives the offline
  /// "continue reading" button; a manga with none downloaded is absent from
  /// the map.
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
      (select(offlineChapters)..where((t) => t.mangaId.equals(mangaId)))
          .watch();

  /// Live stream of every chapter downloaded OR actively downloading/queued —
  /// drives the Downloads → Offline files tab, so in-progress downloads show
  /// too, not just finished ones.
  Stream<List<OfflineChapter>> watchOfflineChapters() =>
      (select(offlineChapters)
            ..where((t) => t.deviceState.isIn([
                  OfflineDeviceState.downloaded.name,
                  OfflineDeviceState.downloading.name,
                  OfflineDeviceState.queued.name,
                ])))
          .watch();

  /// Live list of every series with an offline footprint — chapters present
  /// OR an active keep-rule — with per-series aggregates and the manga row.
  /// The union makes Downloads → On device the single surface: a rule with
  /// nothing downloaded yet still appears, and hand-saved chapters with no
  /// rule still appear.
  Stream<List<({OfflineManga manga, int downloaded, int inFlight, int bytes})>>
      watchOfflineSeries() {
    final downloaded = offlineChapters.id.count(
        filter: offlineChapters.deviceState
            .equalsValue(OfflineDeviceState.downloaded));
    final inFlight = offlineChapters.id.count(
        filter: offlineChapters.deviceState
                .equalsValue(OfflineDeviceState.downloading) |
            offlineChapters.deviceState.equalsValue(OfflineDeviceState.queued));
    final byteSum = offlineChapters.bytes.sum(
        filter: offlineChapters.deviceState
            .equalsValue(OfflineDeviceState.downloaded));
    final query = select(offlineMangas).join([
      leftOuterJoin(
          offlineChapters, offlineChapters.mangaId.equalsExp(offlineMangas.id)),
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
