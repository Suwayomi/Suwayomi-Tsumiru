// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:drift/drift.dart';

import '../../../utils/logger/logger.dart';
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
  TextColumn get keepRule => textEnum<OfflineKeepRule>().withDefault(
    Constant(OfflineKeepRule.off.name),
  )();
  IntColumn get keepUnreadCount => integer().withDefault(const Constant(3))();

  // Server-sourced metadata for offline filters / sort / badges / grouping.
  TextColumn get sourceId => text().nullable()();
  TextColumn get sourceName => text().nullable()();
  TextColumn get sourceLang => text().nullable()();
  // ContentWarning enum name. Null on rows mirrored before the rating existed
  // and never re-synced since; treated as unrated, so the genre tags decide.
  TextColumn get sourceContentWarning => text().nullable()();
  // JSON-encoded tag list. The library's content filter refines a MIXED source
  // on these, so without them the filter behaves differently offline.
  TextColumn get genre => text().nullable()();
  TextColumn get status => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get downloadCount => integer().withDefault(const Constant(0))();
  IntColumn get bookmarkCount => integer().withDefault(const Constant(0))();
  TextColumn get inLibraryAt => text().nullable()();
  TextColumn get latestFetchedAt => text().nullable()();
  TextColumn get latestUploadedAt => text().nullable()();
  // Server-computed lastReadChapter.lastReadAt: the library "Last Read" sort
  // key for series whose chapter list was never synced.
  TextColumn get lastReadAt => text().nullable()();
  // Server manga meta as JSON (per-series reader mode/orientation, rating,
  // tags) — the reader needs this offline too.
  TextColumn get metaJson => text().nullable()();
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
// deviceState is filtered on by chaptersInState/nextQueuedChapter/
// watchOfflineChapters and the watchOfflineSeries join/aggregate — all
// unindexed full scans without this, and (worse) drift's per-table .watch()
// reruns watchOfflineSeries' whole join on every OfflineChapters write, so an
// active download's per-page byte/pageCount updates were driving repeated
// full-table scans of a table that can hold years of chapter metadata.
@TableIndex(name: 'idx_offline_chapter_device_state', columns: {#deviceState})
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
  TextColumn get deviceState => textEnum<OfflineDeviceState>().withDefault(
    Constant(OfflineDeviceState.none.name),
  )();
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

  /// Whether the pending [readStateDirty] change came from a manual mark-read
  /// action (library/updates bulk "mark read") rather than ordinary reading.
  /// Only meaningful while [readStateDirty] is true — read by
  /// [pushPendingProgress] to pick the right tracker-sync gate
  /// (updateProgressManualMarkRead vs updateProgressAfterReading) when
  /// flushing a read-state change that was queued offline; a stale value left
  /// over from a since-cleared write is never consulted.
  BoolColumn get readStateManual =>
      boolean().withDefault(const Constant(false))();

  /// The read state already reflected in the manga row's stored [OfflineMangas
  /// .unreadCount] — NOT simply "what the server last said". Invariant the
  /// offline view depends on: shown unread = stored count − Σ(isRead −
  /// syncedIsRead). Three legal writers, each tied to the count it corrects:
  ///
  ///  1. a chapter down-sync writes it alongside isRead when the row has no
  ///     unsettled local change — first mirrors and changes from another
  ///     device (preserving it there would invent a correction for a change
  ///     this device never made);
  ///  2. [alignSyncedReadBaseline] moves it when an aggregate lands, for rows
  ///     whose acks predate that aggregate's fetch;
  ///  3. [adoptServerReadState] settles it when a local change is abandoned.
  ///
  /// Preserved while a READ change is unsettled — readStateDirty, or the row
  /// still carries a live correction (isRead ≠ baseline) the server is merely
  /// confirming — read off the persisted row so it survives a restart between
  /// an ack and its aggregate. Other dirty flags don't protect it. A push ack
  /// alone must NOT move it: the server knows the change, but the stored
  /// count still predates it, so retiring the correction early re-shows the
  /// old number. Every prior bug here was a writer moving one side of the
  /// invariant without the other — check any new writer against it.
  BoolColumn get syncedIsRead => boolean().withDefault(const Constant(false))();

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

  /// How many times the foreground reconciler has asked the server to fetch
  /// this chapter from its source without serverIsDownloaded ever flipping
  /// true. Persisted (not in-memory) so a chapter whose source is gone for
  /// good doesn't get a fresh budget every app restart — without that, a
  /// user testing across several sessions would see it retried forever, one
  /// or two attempts at a time, never actually reaching the cap that marks
  /// it `error` and stops the request. Reset to 0 once serverIsDownloaded
  /// flips true (a synced-down chapter that succeeded has nothing left to
  /// give up on).
  IntColumn get serverFetchAttempts =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class OfflineCategories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // Mirrors the server's tsumiru.hidden category meta, so hidden tabs stay
  // hidden offline.
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();

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
  int get schemaVersion => 16;

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
          m,
          offlineMangas,
          offlineMangas.keepUnreadCount,
        );
        await _addColumnIfMissing(m, offlineChapters, offlineChapters.pinned);
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.downloadedAt,
        );
      }
      if (from < 3) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.progressDirty,
        );
      }
      if (from < 4) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.lastReadAt,
        );
      }
      if (from < 5) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.bookmarkDirty,
        );
      }
      if (from < 6) {
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.sourceId);
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.sourceName);
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.sourceLang);
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.status);
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.unreadCount);
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.downloadCount,
        );
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.bookmarkCount,
        );
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.inLibraryAt);
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.latestFetchedAt,
        );
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.latestUploadedAt,
        );
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.totalChapters,
        );
      }
      if (from < 7) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.readStateDirty,
        );
        // Carry pending reads across the split: a progress-dirty row with
        // isRead=true is usually a completed offline read awaiting push
        // (it may also be a server-sourced true on a partial re-read —
        // pushing true is the safe direction). is_read=0 dirty rows are
        // exactly the stale class; they stay position-only.
        await customStatement(
          'UPDATE offline_chapters SET read_state_dirty = 1 '
          'WHERE progress_dirty = 1 AND is_read = 1',
        );
      }
      if (from < 8) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.downloadGeneration,
        );
      }
      if (from < 10) {
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.lastReadAt);
      }
      if (from < 11) {
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.metaJson);
      }
      if (from < 9) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.chapterNumber,
        );
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.scanlator,
        );
      }
      if (from < 13 && await _hasTable(offlineMangas)) {
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.sourceContentWarning,
        );
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.genre);
        // Carry the old boolean forward (present only on devices that passed
        // through schemas 6-9). true maps to NSFW, not MIXED, matching what
        // the old filter did and erring toward hiding over an untested tag.
        if (await _hasColumn(offlineMangas, 'source_is_nsfw')) {
          await customStatement(
            "UPDATE offline_mangas SET source_content_warning = "
            "CASE WHEN source_is_nsfw THEN 'NSFW' ELSE 'SAFE' END "
            "WHERE source_content_warning IS NULL",
          );
        }
      }
      // Interim dev builds from two branches each stamped version 10/11 with
      // DIFFERENT columns, so a device's version number doesn't say which
      // columns it has. v12 re-checks every column from that era; the adds
      // are idempotent and the backfills below guard on the column having
      // been missing.
      if (from < 12) {
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.lastReadAt);
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.metaJson);
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.sourceContentWarning,
        );
        await _addColumnIfMissing(m, offlineMangas, offlineMangas.genre);
        final hadSyncedIsRead = await _hasColumn(
          offlineChapters,
          'synced_is_read',
        );
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.syncedIsRead,
        );
        if (!hadSyncedIsRead) {
          await customStatement(
            'UPDATE offline_chapters SET synced_is_read = is_read',
          );
        }
      }
      // NOTE: a second `if (from < 10)` step used to duplicate this exact
      // add-column-then-backfill for synced_is_read. Removed (2026) — the
      // `if (from < 12)` block above already covers every from<10 upgrade
      // (12 > 10) with the SAME guarded backfill (only runs when the column
      // was actually missing), so the second copy only ever re-ran a no-op
      // unconditional UPDATE. Harmless today, but this invariant has broken
      // from exactly this shape of duplicate writer before — don't re-add it.
      if (from < 14) {
        // onCreate only runs for brand-new databases, so an upgrade from a
        // version without these tables has to create them itself.
        if (await _hasTable(offlineCategories)) {
          await _addColumnIfMissing(
            m,
            offlineCategories,
            offlineCategories.isHidden,
          );
        } else {
          await m.createTable(offlineCategories);
        }
        if (!await _hasTable(offlineMangaCategories)) {
          await m.createTable(offlineMangaCategories);
        }
      }
      if (from < 15) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.readStateManual,
        );
      }
      if (from < 15 && !await _hasIndex('idx_offline_chapter_device_state')) {
        await m.createIndex(idxOfflineChapterDeviceState);
      }
      if (from < 16) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.serverFetchAttempts,
        );
      }
    },
  );

  /// A migration step must not explode on a table this database has never
  /// created — schema fixtures and partial upgrades both hit that.
  Future<bool> _hasTable(TableInfo table) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      variables: [Variable<String>(table.actualTableName)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Same idempotency concern as [_hasTable]/[_addColumnIfMissing]: an
  /// intermediate/dev build can leave an index present at an older recorded
  /// schema version, and `CREATE INDEX` (unlike `addColumn`) has no built-in
  /// "if missing" guard in drift's Migrator.
  Future<bool> _hasIndex(String name) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='index' AND name=?",
      variables: [Variable<String>(name)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _hasColumn(TableInfo table, String columnName) async {
    final info = await customSelect(
      "PRAGMA table_info('${table.actualTableName}')",
    ).get();
    return info.any((row) => row.read<String>('name') == columnName);
  }

  /// drift's [Migrator.addColumn] throws if the column already exists — a
  /// device migrated by an intermediate/dev build can have it present at an
  /// older recorded schema version, so guard each add to stay idempotent.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final info = await customSelect(
      "PRAGMA table_info('${table.actualTableName}')",
    ).get();
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
    String? sourceContentWarning,
    String? genre,
    String? status,
    int unreadCount = 0,
    int downloadCount = 0,
    int bookmarkCount = 0,
    String? inLibraryAt,
    String? latestFetchedAt,
    String? latestUploadedAt,
    String? lastReadAt,
    String? metaJson,
    int totalChapters = 0,
  }) => into(offlineMangas).insertOnConflictUpdate(
    OfflineMangasCompanion(
      id: Value(id),
      title: Value(title),
      updatedAt: Value(updatedAt),
      thumbnailUrl: thumbnailUrl == null
          ? const Value.absent()
          : Value(thumbnailUrl),
      // device-managed: thumbnailRelPath, keepRule, keepUnreadCount stay absent
      sourceId: Value(sourceId),
      sourceName: Value(sourceName),
      sourceLang: Value(sourceLang),
      sourceContentWarning: Value(sourceContentWarning),
      genre: Value(genre),
      status: Value(status),
      unreadCount: Value(unreadCount),
      downloadCount: Value(downloadCount),
      bookmarkCount: Value(bookmarkCount),
      inLibraryAt: Value(inLibraryAt),
      latestFetchedAt: Value(latestFetchedAt),
      latestUploadedAt: Value(latestUploadedAt),
      // '0'/null means "no signal", not "erase": a catalog-served DTO echoed
      // back through sync must never null a stored read timestamp.
      lastReadAt: (lastReadAt == null || lastReadAt == '0')
          ? const Value.absent()
          : Value(lastReadAt),
      metaJson: Value(metaJson),
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
    // The server's own value, recorded even when [isRead] carries a preserved
    // local change, so the two can be compared later.
    bool? syncedIsRead,
  }) => into(offlineChapters).insertOnConflictUpdate(
    OfflineChaptersCompanion(
      id: Value(id),
      mangaId: Value(mangaId),
      name: Value(name),
      chapterIndex: Value(chapterIndex),
      syncedIsRead: syncedIsRead == null
          ? const Value.absent()
          : Value(syncedIsRead),
      // Absent when omitted (like lastReadAt): a caller that doesn't carry
      // these must not null-clobber values a full sync already wrote.
      chapterNumber: chapterNumber == null
          ? const Value.absent()
          : Value(chapterNumber),
      scanlator: scanlator == null ? const Value.absent() : Value(scanlator),
      isRead: Value(isRead),
      lastPageRead: Value(lastPageRead),
      isBookmarked: Value(isBookmarked),
      serverIsDownloaded: Value(serverIsDownloaded),
      pageCount: Value(pageCount),
      updatedAt: Value(updatedAt),
      // '0' (the offline DTO mapper's "no signal" value) and null must not
      // erase a stored read timestamp.
      lastReadAt: (lastReadAt == null || lastReadAt == '0')
          ? const Value.absent()
          : Value(lastReadAt),
      // deviceState + bytes intentionally absent — device-managed.
    ),
  );

  Future<void> upsertCategory(
    int id,
    String name,
    int sortOrder, {
    required bool isHidden,
  }) => into(offlineCategories).insertOnConflictUpdate(
    OfflineCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      isHidden: Value(isHidden),
    ),
  );

  /// Device-local visibility override while offline. The next online
  /// [OfflineSync.syncCategories] reasserts the server's flag. False when no
  /// mirrored row matched — callers must not report success then.
  Future<bool> setCategoryHidden(int id, bool hidden) async {
    final rows =
        await (update(offlineCategories)..where((t) => t.id.equals(id))).write(
          OfflineCategoriesCompanion(isHidden: Value(hidden)),
        );
    return rows > 0;
  }

  /// Drop categories the server no longer has, membership rows included.
  /// Callers guard against an empty [serverIds] — a failed fetch must never
  /// wipe the mirror.
  Future<void> pruneRemovedCategories(Set<int> serverIds) =>
      transaction(() async {
        await (delete(
          offlineMangaCategories,
        )..where((t) => t.categoryId.isNotIn(serverIds))).go();
        await (delete(
          offlineCategories,
        )..where((t) => t.id.isNotIn(serverIds))).go();
      });

  /// Downloaded-library manga per category, for the offline tab counts.
  /// Membership rows outside [mangaIds] don't count.
  Future<Map<int, int>> mangaCountByCategory(Set<int> mangaIds) async {
    if (mangaIds.isEmpty) return {};
    final categoryId = offlineMangaCategories.categoryId;
    final mangaCount = offlineMangaCategories.mangaId.count();
    final query = selectOnly(offlineMangaCategories)
      ..addColumns([categoryId, mangaCount])
      ..where(offlineMangaCategories.mangaId.isIn(mangaIds))
      ..groupBy([categoryId]);
    final counts = <int, int>{};
    for (final row in await query.get()) {
      counts[row.read(categoryId)!] = row.read(mangaCount) ?? 0;
    }
    return counts;
  }

  /// Of [mangaIds], the ones with no membership in a STORED category — these
  /// render under Default. A row pointing at a pruned/unmirrored category
  /// doesn't count either; the mapper's inner join drops it the same way.
  Future<Set<int>> uncategorizedOf(Set<int> mangaIds) async {
    if (mangaIds.isEmpty) return {};
    final rows = await (select(offlineMangaCategories).join([
      innerJoin(
        offlineCategories,
        offlineCategories.id.equalsExp(offlineMangaCategories.categoryId),
      ),
    ])
          ..where(offlineMangaCategories.mangaId.isIn(mangaIds)))
        .get();
    final categorized = {
      for (final row in rows) row.readTable(offlineMangaCategories).mangaId,
    };
    return mangaIds.difference(categorized);
  }

  /// Replace a manga's full category membership atomically (delete-then-insert).
  /// Safe to call with an empty list — just removes all memberships.
  Future<void> replaceMangaCategories(int mangaId, List<int> categoryIds) =>
      transaction(() async {
        await (delete(
          offlineMangaCategories,
        )..where((t) => t.mangaId.equals(mangaId))).go();
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
    ])..orderBy([OrderingTerm(expression: offlineCategories.sortOrder)]);
    return (await query.get())
        .map((row) => row.readTable(offlineCategories))
        .toList();
  }

  /// Batched form of [categoriesForManga]: one join query covering every id
  /// in [mangaIds] instead of one round-trip per manga. A manga with no
  /// entry in the result has no categories (same meaning as an empty list
  /// from the single-id form).
  Future<Map<int, List<OfflineCategory>>> categoriesForMangas(
    Set<int> mangaIds,
  ) async {
    if (mangaIds.isEmpty) return {};
    final query = select(offlineMangaCategories).join([
      innerJoin(
        offlineCategories,
        offlineCategories.id.equalsExp(offlineMangaCategories.categoryId),
      ),
    ])
      ..where(offlineMangaCategories.mangaId.isIn(mangaIds))
      ..orderBy([OrderingTerm(expression: offlineCategories.sortOrder)]);
    final byManga = <int, List<OfflineCategory>>{};
    for (final row in await query.get()) {
      final mangaId = row.readTable(offlineMangaCategories).mangaId;
      byManga.putIfAbsent(mangaId, () => []).add(row.readTable(offlineCategories));
    }
    return byManga;
  }

  /// All persisted categories — for the offline category-list fallback.
  Future<List<OfflineCategory>> allOfflineCategories() => (select(
    offlineCategories,
  )..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).get();

  // --- device-managed mutations ---------------------------------------------

  Future<void> setMangaCoverPath(int mangaId, String relPath) =>
      (update(offlineMangas)..where((t) => t.id.equals(mangaId))).write(
        OfflineMangasCompanion(thumbnailRelPath: Value(relPath)),
      );

  Future<void> setKeepRule(int mangaId, OfflineKeepRule rule, int count) =>
      (update(offlineMangas)..where((t) => t.id.equals(mangaId))).write(
        OfflineMangasCompanion(
          keepRule: Value(rule),
          keepUnreadCount: Value(count),
        ),
      );

  Future<void> setChapterPinned(int chapterId, bool pinned) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(pinned: Value(pinned)),
      );

  /// Set a chapter's resolved page count — drives the determinate download
  /// progress arc for chapters (e.g. webtoon) whose total wasn't known until
  /// the downloader resolved their pages.
  Future<void> setChapterPageCount(int chapterId, int pageCount) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(pageCount: Value(pageCount)),
      );

  Future<void> setChapterDeviceState(
    int chapterId,
    OfflineDeviceState state, {
    int? bytes,
    DateTime? downloadedAt,
  }) => (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
    OfflineChaptersCompanion(
      deviceState: Value(state),
      bytes: bytes == null ? const Value.absent() : Value(bytes),
      downloadedAt: downloadedAt == null
          ? const Value.absent()
          : Value(downloadedAt),
    ),
  );

  /// Bumps [OfflineChapters.serverFetchAttempts] by one — called each time the
  /// reconciler actually asks the server to fetch a chapter it has never
  /// managed to download, so the count survives an app restart instead of
  /// resetting to a fresh budget every session.
  Future<void> incrementServerFetchAttempts(int chapterId) => customUpdate(
    'UPDATE offline_chapters SET server_fetch_attempts = server_fetch_attempts + 1 '
    'WHERE id = ?',
    variables: [Variable<int>(chapterId)],
    updates: {offlineChapters},
  );

  /// Clears [OfflineChapters.serverFetchAttempts] — called once a chapter's
  /// server fetch actually succeeds, so a later unrelated failure starts its
  /// budget fresh rather than inheriting attempts spent on a since-resolved
  /// problem.
  Future<void> resetServerFetchAttempts(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        const OfflineChaptersCompanion(serverFetchAttempts: Value(0)),
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
  }) => transaction(() async {
    await (delete(
      offlinePages,
    )..where((t) => t.chapterId.equals(toChapterId))).go();
    for (final pg in pages) {
      await into(offlinePages).insertOnConflictUpdate(
        OfflinePagesCompanion(
          chapterId: Value(toChapterId),
          pageIndex: Value(pg.pageIndex),
          relativePath: Value(pg.relPath),
        ),
      );
    }
    await (update(
      offlineChapters,
    )..where((t) => t.id.equals(toChapterId))).write(
      OfflineChaptersCompanion(
        deviceState: const Value(OfflineDeviceState.downloaded),
        bytes: Value(pages.fold<int>(0, (s, p) => s + p.bytes)),
        pageCount: Value(pages.length),
        downloadedAt: Value(downloadedAt),
        pinned: Value(pinned),
      ),
    );
    if (clearSourceChapterId != null) {
      await (delete(
        offlinePages,
      )..where((t) => t.chapterId.equals(clearSourceChapterId))).go();
      await (update(
        offlineChapters,
      )..where((t) => t.id.equals(clearSourceChapterId))).write(
        const OfflineChaptersCompanion(
          deviceState: Value(OfflineDeviceState.none),
          bytes: Value(0),
        ),
      );
    }
  });

  /// Record a chapter whose staging directory was just promoted: its page rows
  /// and its `downloaded` state land in ONE transaction, so the catalog never
  /// half-knows about a chapter.
  ///
  /// Page rows are written here and nowhere else during a download — they point
  /// at the final directory, which only exists once the rename has happened.
  /// [pageCount] is set from what was actually committed rather than left to
  /// the server's value, so the row describes the copy on this device.
  Future<void> commitDownloadedChapter({
    required int chapterId,
    required List<({int pageIndex, String relPath, int bytes})> pages,
    required DateTime downloadedAt,
  }) async {
    // Downloaded-with-no-pages reads as local but resolves to nothing, so the
    // reader streams every page from the server instead. A torn manifest is
    // enough to produce it, via committedPages returning [].
    if (pages.isEmpty) {
      logger.w(
        'Offline: refusing to mark chapter $chapterId downloaded with no pages',
      );
      return;
    }
    return transaction(() async {
      await (delete(
        offlinePages,
      )..where((t) => t.chapterId.equals(chapterId))).go();
      for (final pg in pages) {
        await into(offlinePages).insertOnConflictUpdate(
          OfflinePagesCompanion.insert(
            chapterId: chapterId,
            pageIndex: pg.pageIndex,
            relativePath: pg.relPath,
          ),
        );
      }
      await (update(
        offlineChapters,
      )..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          deviceState: const Value(OfflineDeviceState.downloaded),
          bytes: Value(pages.fold<int>(0, (s, p) => s + p.bytes)),
          pageCount: Value(pages.length),
          downloadedAt: Value(downloadedAt),
        ),
      );
    });
  }

  /// Unpin every chapter of a manga — used on Migrate so the source's kept
  /// chapters aren't held back from the post-removal purge reconcile.
  Future<void> unpinChaptersForManga(int mangaId) =>
      (update(offlineChapters)..where((t) => t.mangaId.equals(mangaId))).write(
        const OfflineChaptersCompanion(pinned: Value(false)),
      );

  /// Bump a chapter's persistent download generation and return the new
  /// value — called on every delete so a re-queued download outranks any
  /// still-in-flight event, and persisted so it survives a restart.
  Future<int> bumpChapterGeneration(int chapterId) => transaction(() async {
    final current = await chapterById(chapterId);
    final next = (current?.downloadGeneration ?? 0) + 1;
    await (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
      OfflineChaptersCompanion(downloadGeneration: Value(next)),
    );
    return next;
  });

  /// Record local reading progress (read offline / always). Marks it
  /// `progressDirty` so it's pushed to the server on the next online sync.
  ///
  /// [manual] records whether this read-state change came from a manual
  /// mark-read action (bulk "mark read" with a position reset) rather than
  /// ordinary reading — [pushPendingProgress] reads it back to pick the right
  /// tracker-sync gate when flushing offline-queued read-state changes.
  /// Ignored (never written) when [isRead] is null, matching [readStateDirty]
  /// itself: a partial position-only write has no read-state provenance to
  /// record.
  Future<void> setChapterProgress(
    int chapterId, {
    required int lastPageRead,
    bool? isRead,
    bool manual = false,
  }) => (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
    OfflineChaptersCompanion(
      lastPageRead: Value(lastPageRead),
      progressDirty: const Value(true),
      // Bump Last Read locally (epoch seconds, matching the server's unit) so
      // the offline sort has a signal until the next down-sync overwrites it.
      lastReadAt: Value(_nowEpochSeconds()),
      // null → leave read-state untouched (a partial write must not
      // un-read); a read-state change rides its OWN flag so position-only
      // writes can't push a stale isRead (the ch-99 loop).
      isRead: isRead == null ? const Value.absent() : Value(isRead),
      readStateDirty: isRead == null ? const Value.absent() : const Value(true),
      readStateManual:
          isRead == null ? const Value.absent() : Value(manual),
    ),
  );

  static String _nowEpochSeconds() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  /// Record a local read/unread change (list actions, mark-read). Position
  /// untouched; pushed under its own flag on the next online sync.
  ///
  /// [manual] is true for every caller of this method today (it's only ever
  /// invoked from the manual mark-read path — ordinary reading progress goes
  /// through [setChapterProgress] instead) — see that method's doc comment
  /// for what it's used for.
  Future<void> setChapterReadState(
    int chapterId,
    bool isRead, {
    bool manual = true,
  }) => (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          isRead: Value(isRead),
          readStateDirty: const Value(true),
          readStateManual: Value(manual),
          // Marking read counts as reading activity for the Last Read sort;
          // un-reading is bookkeeping and leaves the timestamp alone.
          lastReadAt: isRead ? Value(_nowEpochSeconds()) : const Value.absent(),
        ),
      );

  /// Read-state changes this device has made that the manga's server-side
  /// `unreadCount` does not know about yet, as `newly read - newly unread`.
  ///
  /// Measured against [OfflineChapters.syncedIsRead], the last value the
  /// server reported, so it is exact in both directions and for any subset of
  /// chapters: re-reading something already read counts zero, un-reading
  /// raises the count, and a partial mirror corrects the chapters it holds
  /// without having to reason about the ones it does not.
  Future<Map<int, int>> unsyncedReadDeltaByManga() async {
    // Only mismatched rows contribute, so filter in SQL — the read rows of a
    // whole library are thousands; the pending changes are a handful.
    final rows = await (select(
      offlineChapters,
    )..where((t) => t.isRead.equalsExp(t.syncedIsRead).not())).get();
    final delta = <int, int>{};
    for (final r in rows) {
      delta[r.mangaId] = (delta[r.mangaId] ?? 0) + (r.isRead ? 1 : -1);
    }
    return delta;
  }

  /// Clear the progress dirty flag after the progress was pushed to the server.
  Future<void> clearProgressDirty(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        const OfflineChaptersCompanion(progressDirty: Value(false)),
      );

  /// Clear the bookmark dirty flag after the bookmark was pushed to the server.
  Future<void> clearBookmarkDirty(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        const OfflineChaptersCompanion(bookmarkDirty: Value(false)),
      );

  /// Clear progressDirty only if the row still holds the exact pushed values —
  /// so a newer local write landing mid-push isn't marked clean and lost (the
  /// snapshot-then-clear race); a non-matching row keeps its flag and re-syncs.
  Future<void> clearProgressDirtyIfUnchanged(
    int chapterId, {
    required int lastPageRead,
  }) =>
      (update(offlineChapters)..where(
            (t) => t.id.equals(chapterId) & t.lastPageRead.equals(lastPageRead),
          ))
          .write(const OfflineChaptersCompanion(progressDirty: Value(false)));

  /// Orders push acknowledgements against refresh fetches, so the baseline
  /// alignment can tell which acked changes a fetched aggregate can possibly
  /// contain. In-memory on purpose: the ordering only matters within one
  /// session (a push and a refresh can only race while both are in flight),
  /// and an ack from a previous run is by definition older than any fetch in
  /// this one — which is exactly what an absent entry means.
  int _pushGen = 0;
  final Map<int, int> _ackGen = {};

  /// Capture BEFORE issuing the network fetch whose result will be handed to
  /// the sync layer. Captured too late, and the alignment trusts an aggregate
  /// with changes it cannot have seen — the premature-retire bug.
  int get syncGeneration => _pushGen;

  /// Clear readStateDirty only if the row's isRead still matches what was
  /// pushed — the same race guard as [clearProgressDirtyIfUnchanged], mirroring
  /// [clearBookmarkDirtyIfUnchanged].
  Future<void> clearReadStateDirtyIfUnchanged(
    int chapterId, {
    required bool isRead,
  }) async {
    final matched =
        await (update(offlineChapters)
              ..where((t) => t.id.equals(chapterId) & t.isRead.equals(isRead)))
            .write(
              // Deliberately does NOT move syncedIsRead. The push is known to
              // the server but the manga's stored unreadCount still is not, so
              // the correction has to survive until that aggregate is
              // refreshed — see alignSyncedReadBaseline, which retires it.
              const OfflineChaptersCompanion(readStateDirty: Value(false)),
            );
    // Stamp the ack only if the clear applied — a mid-push local write keeps
    // its flag, stays out of alignment via the dirty check, and re-acks on the
    // next pass with a fresh stamp.
    if (matched > 0) _ackGen[chapterId] = ++_pushGen;
  }

  /// Retire corrections whose change the refreshed aggregate already counts.
  ///
  /// Called when a manga's server-side counts are written; [upToGen] is the
  /// sync generation captured before that aggregate's fetch went out. Two
  /// kinds of row keep their baseline, and so keep correcting:
  ///
  ///  - rows still dirty (the push has not happened), and
  ///  - rows whose push was acknowledged only after the fetch started — the
  ///    server committed the change after (or while) it served this
  ///    aggregate, so the count in hand cannot be assumed to include it.
  ///
  /// Everything else is the server's own value as of a fetch that started
  /// after its ack, so the refreshed count provably contains it and the
  /// correction retires.
  /// Returns how many of this manga's live corrections were left in place
  /// because their acks postdate the aggregate's fetch — the caller can then
  /// refetch with a later generation to settle them promptly.
  Future<int> alignSyncedReadBaseline(
    int mangaId, {
    required int upToGen,
  }) async {
    final lateAcks = [
      for (final e in _ackGen.entries)
        if (e.value > upToGen) e.key,
    ];
    var skipped = 0;
    if (lateAcks.isNotEmpty) {
      skipped =
          (await (select(offlineChapters)..where(
                    (t) =>
                        t.mangaId.equals(mangaId) &
                        t.readStateDirty.equals(false) &
                        t.id.isIn(lateAcks) &
                        t.isRead.equalsExp(t.syncedIsRead).not(),
                  ))
                  .get())
              .length;
    }
    final placeholders = List.filled(lateAcks.length, '?').join(', ');
    await customStatement(
      'UPDATE offline_chapters SET synced_is_read = is_read '
      'WHERE manga_id = ? AND read_state_dirty = 0'
      '${lateAcks.isEmpty ? '' : ' AND id NOT IN ($placeholders)'}',
      [mangaId, ...lateAcks],
    );
    return skipped;
  }

  /// Full rows for [ids], keyed by id. Chunked: chapter lists can exceed
  /// SQLite's bound-variable limit.
  Future<Map<int, OfflineChapter>> chaptersByIds(List<int> ids) async {
    final found = <int, OfflineChapter>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final rows = await (select(
        offlineChapters,
      )..where((t) => t.id.isIn(chunk))).get();
      for (final r in rows) {
        found[r.id] = r;
      }
    }
    return found;
  }

  /// Settle a row whose local change LOST — the never-regress policy found the
  /// server ahead and dropped the push. A one-row down-sync of the state we
  /// just fetched: live value, position, and baseline all become the server's,
  /// so the correction retires with the change instead of arguing for it
  /// forever. Clearing the dirty flag alone is not enough — that freezes
  /// isRead != syncedIsRead with nothing left that would ever reconcile them.
  ///
  /// Guarded on the values the sync pass examined, like the IfUnchanged
  /// clears: a newer local write mid-pass keeps its flag and re-resolves on
  /// the next pass instead of being silently overwritten.
  Future<void> adoptServerReadState(
    int chapterId, {
    required bool expectedIsRead,
    required int expectedLastPageRead,
    required bool serverIsRead,
    required int serverLastPageRead,
  }) =>
      (update(offlineChapters)..where(
            (t) =>
                t.id.equals(chapterId) &
                t.isRead.equals(expectedIsRead) &
                t.lastPageRead.equals(expectedLastPageRead),
          ))
          .write(
            OfflineChaptersCompanion(
              isRead: Value(serverIsRead),
              lastPageRead: Value(serverLastPageRead),
              syncedIsRead: Value(serverIsRead),
              progressDirty: const Value(false),
              readStateDirty: const Value(false),
            ),
          );

  /// Clear bookmarkDirty only if the bookmark still matches what was pushed —
  /// same race guard as [clearProgressDirtyIfUnchanged].
  Future<void> clearBookmarkDirtyIfUnchanged(
    int chapterId, {
    required bool isBookmarked,
  }) =>
      (update(offlineChapters)..where(
            (t) => t.id.equals(chapterId) & t.isBookmarked.equals(isBookmarked),
          ))
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
  Future<List<OfflineChapter>> dirtyProgressChapters() => (select(
    offlineChapters,
  )..where((t) => t.progressDirty.equals(true))).get();

  /// Chapters with any unpushed local change — read progress OR bookmark — for
  /// the up-sync to flush and the down-sync to preserve.
  Future<List<OfflineChapter>> dirtyChapters() =>
      (select(offlineChapters)..where(
            (t) =>
                t.progressDirty.equals(true) |
                t.bookmarkDirty.equals(true) |
                t.readStateDirty.equals(true),
          ))
          .get();

  // --- offline queries -------------------------------------------------------

  Future<OfflineManga?> mangaById(int mangaId) => (select(
    offlineMangas,
  )..where((t) => t.id.equals(mangaId))).getSingleOrNull();

  Future<OfflineChapter?> chapterById(int chapterId) => (select(
    offlineChapters,
  )..where((t) => t.id.equals(chapterId))).getSingleOrNull();

  Future<List<OfflineManga>> libraryManga() =>
      (select(offlineMangas)
            // '0' means explicitly removed (see markNotInLibrary) — those rows
            // survive only for their downloads and must not resurface here.
            ..where(
              (t) => t.inLibraryAt.equals('0').not() | t.inLibraryAt.isNull(),
            )
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

  /// Stamps '0' (explicitly removed) on every catalog manga NOT in
  /// [libraryIds] — the mark half of pruning removed-from-library manga.
  /// [purgeRemovedLibraryManga] then deletes the ones with nothing
  /// downloaded. Distinct from NULL, which means "synced before the column
  /// existed" and must keep counting as a library entry.
  Future<int> markNotInLibrary(Set<int> libraryIds) =>
      (update(offlineMangas)..where((t) => t.id.isNotIn(libraryIds))).write(
        const OfflineMangasCompanion(inLibraryAt: Value('0')),
      );

  /// Deletes explicitly-removed manga with nothing downloaded. Scoped to the
  /// '0' mark so it can run concurrently with the per-manga metadata upserts
  /// of the same sync pass without racing legacy NULL rows they haven't
  /// stamped yet.
  Future<int> purgeRemovedLibraryManga() => transaction(() async {
    final withDeviceContent = selectOnly(offlineChapters)
      ..addColumns([offlineChapters.mangaId])
      ..where(
        offlineChapters.deviceState.equalsValue(OfflineDeviceState.none).not(),
      );
    final doomed =
        await (selectOnly(offlineMangas)
              ..addColumns([offlineMangas.id])
              ..where(
                offlineMangas.inLibraryAt.equals('0') &
                    offlineMangas.id.isNotInQuery(withDeviceContent),
              ))
            .map((r) => r.read(offlineMangas.id)!)
            .get();
    if (doomed.isEmpty) return 0;
    // Rows being deleted have no device content, so their chapter and
    // category rows are metadata-only — sweep them too or the catalog
    // grows forever.
    await (delete(offlineChapters)..where((t) => t.mangaId.isIn(doomed))).go();
    await (delete(
      offlineMangaCategories,
    )..where((t) => t.mangaId.isIn(doomed))).go();
    return (delete(offlineMangas)..where((t) => t.id.isIn(doomed))).go();
  });

  /// Sweep browsed-not-added manga a past bug wrote here: no library timestamp
  /// and nothing downloaded. Never touches downloads — a swept stray row just
  /// re-mirrors on the next online load.
  Future<int> purgeNonLibraryManga() {
    final withDeviceContent = selectOnly(offlineChapters)
      ..addColumns([offlineChapters.mangaId])
      ..where(
        offlineChapters.deviceState.equalsValue(OfflineDeviceState.none).not(),
      );
    return (delete(offlineMangas)..where(
          (t) =>
              (t.inLibraryAt.isNull() | t.inLibraryAt.equals('0')) &
              t.id.isNotInQuery(withDeviceContent),
        ))
        .go();
  }

  /// Most-recent read timestamp per manga (max chapter `lastReadAt`), for the
  /// offline library's "Last Read" sort — absent for mangas with no read
  /// chapter. Values are epoch-seconds strings (the server's unit), so the max
  /// is taken numerically.
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
    final rows =
        await (select(offlineChapters)
              ..where(
                (t) =>
                    t.isRead.equals(false) &
                    t.deviceState.equalsValue(OfflineDeviceState.downloaded),
              )
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
  Stream<List<OfflineChapter>> watchChaptersForManga(int mangaId) => (select(
    offlineChapters,
  )..where((t) => t.mangaId.equals(mangaId))).watch();

  /// Live stream of every chapter downloaded OR actively downloading/queued —
  /// drives the Downloads → Offline files tab, so in-progress downloads show
  /// too, not just finished ones.
  Stream<List<OfflineChapter>> watchOfflineChapters() =>
      (select(offlineChapters)..where(
            (t) => t.deviceState.isIn([
              OfflineDeviceState.downloaded.name,
              OfflineDeviceState.downloading.name,
              OfflineDeviceState.queued.name,
            ]),
          ))
          .watch();

  /// Live list of every series with an offline footprint — chapters present
  /// OR an active keep-rule — with per-series aggregates and the manga row.
  /// The union makes Downloads → On device the single surface: a rule with
  /// nothing downloaded yet still appears, and hand-saved chapters with no
  /// rule still appear.
  Stream<List<({OfflineManga manga, int downloaded, int inFlight, int bytes})>>
  watchOfflineSeries() {
    final downloaded = offlineChapters.id.count(
      filter: offlineChapters.deviceState.equalsValue(
        OfflineDeviceState.downloaded,
      ),
    );
    final inFlight = offlineChapters.id.count(
      filter:
          offlineChapters.deviceState.equalsValue(
            OfflineDeviceState.downloading,
          ) |
          offlineChapters.deviceState.equalsValue(OfflineDeviceState.queued),
    );
    final byteSum = offlineChapters.bytes.sum(
      filter: offlineChapters.deviceState.equalsValue(
        OfflineDeviceState.downloaded,
      ),
    );
    final query =
        select(offlineMangas).join([
            leftOuterJoin(
              offlineChapters,
              offlineChapters.mangaId.equalsExp(offlineMangas.id),
            ),
          ])
          ..addColumns([downloaded, inFlight, byteSum])
          ..groupBy(
            [offlineMangas.id],
            // Keep series that have files OR a rule; drop the rest of the library.
            having:
                downloaded.isBiggerThanValue(0) |
                inFlight.isBiggerThanValue(0) |
                offlineMangas.keepRule.equalsValue(OfflineKeepRule.off).not(),
          );
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (
            manga: row.readTable(offlineMangas),
            downloaded: row.read(downloaded) ?? 0,
            inFlight: row.read(inFlight) ?? 0,
            bytes: row.read(byteSum) ?? 0,
          ),
      ],
    );
  }

  /// How many pages of a chapter are already on disk. Cheap COUNT (no row
  /// materialisation) — called on the main isolate on every page completion.
  Future<int> downloadedPageCount(int chapterId) async {
    final cnt = offlinePages.pageIndex.count();
    final row =
        await (selectOnly(offlinePages)
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
  Future<OfflineChapter?> nextQueuedChapter() =>
      (select(offlineChapters)
            ..where((t) => t.deviceState.equalsValue(OfflineDeviceState.queued))
            ..orderBy([
              (t) => OrderingTerm(expression: t.mangaId),
              (t) => OrderingTerm(expression: t.chapterIndex),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<List<OfflineChapter>> downloadedChaptersForManga(int mangaId) =>
      (select(offlineChapters)..where(
            (t) =>
                t.mangaId.equals(mangaId) &
                t.deviceState.equalsValue(OfflineDeviceState.downloaded),
          ))
          .get();

  /// Manga ids that have at least one chapter with [OfflineDeviceState.downloaded]
  /// on this device — used by the "On device" library filter.
  Future<Set<int>> mangaIdsWithDeviceDownloads() async {
    final rows =
        await (selectOnly(offlineChapters, distinct: true)
              ..addColumns([offlineChapters.mangaId])
              ..where(
                offlineChapters.deviceState.equalsValue(
                  OfflineDeviceState.downloaded,
                ),
              ))
            .get();
    return {for (final r in rows) r.read(offlineChapters.mangaId)!};
  }

  /// Live version of [mangaIdsWithDeviceDownloads] — the Library screen's
  /// on-device badge/filter previously only read this once (on provider
  /// creation), so a chapter finishing its download elsewhere (manga details,
  /// Downloads screen) never updated it until the next navigation/manual
  /// refresh. Watching lets it update the moment a chapter's deviceState
  /// flips to downloaded.
  Stream<Set<int>> watchMangaIdsWithDeviceDownloads() {
    final query = selectOnly(offlineChapters, distinct: true)
      ..addColumns([offlineChapters.mangaId])
      ..where(
        offlineChapters.deviceState.equalsValue(
          OfflineDeviceState.downloaded,
        ),
      );
    return query.watch().map(
      (rows) => {for (final r in rows) r.read(offlineChapters.mangaId)!},
    );
  }

  /// Total bytes used by downloaded chapters — for the storage UI, without a
  /// filesystem walk.
  Future<int> totalDownloadedBytes() async {
    final sum = offlineChapters.bytes.sum();
    final row =
        await (selectOnly(offlineChapters)
              ..addColumns([sum])
              ..where(
                offlineChapters.deviceState.equalsValue(
                  OfflineDeviceState.downloaded,
                ),
              ))
            .getSingle();
    return row.read(sum) ?? 0;
  }
}
