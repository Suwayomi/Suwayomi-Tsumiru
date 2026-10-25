// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../utils/crash/diagnostics.dart';
import '../../../utils/logger/logger.dart';
import 'offline_types.dart';

export 'offline_types.dart';

part 'offline_database.g.dart';

/// Explicit library removal; NULL still counts as present, and server timestamp '0' is valid.
const kLibraryRemovedSentinel = '-1';

class OfflineMangas extends Table {
  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get thumbnailUrl => text().nullable()();
  // Server cover version for the cache key; null draws the unversioned key.
  TextColumn get thumbnailUrlLastFetched => text().nullable()();
  TextColumn get thumbnailRelPath => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get keepRule => textEnum<OfflineKeepRule>().withDefault(
    Constant(OfflineKeepRule.off.name),
  )();
  IntColumn get keepUnreadCount => integer().withDefault(const Constant(3))();

  TextColumn get sourceId => text().nullable()();
  TextColumn get sourceName => text().nullable()();
  TextColumn get sourceLang => text().nullable()();
  // Null means unrated; genre tags determine the content warning.
  TextColumn get sourceContentWarning => text().nullable()();
  // JSON-encoded tags refine content warnings for MIXED sources.
  TextColumn get genre => text().nullable()();
  TextColumn get status => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get downloadCount => integer().withDefault(const Constant(0))();
  IntColumn get bookmarkCount => integer().withDefault(const Constant(0))();
  TextColumn get inLibraryAt => text().nullable()();
  TextColumn get latestFetchedAt => text().nullable()();
  TextColumn get latestUploadedAt => text().nullable()();
  // Server sort key for series whose chapter list has never synced.
  TextColumn get lastReadAt => text().nullable()();
  TextColumn get metaJson => text().nullable()();
  IntColumn get totalChapters => integer().withDefault(const Constant(0))();

  // Cache the sort axis for reconciliation and background snapshots; direction is display-only.
  TextColumn get chapterSortMode => textEnum<ChapterSortAxis>().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Keyed by stable server id; orphaned chapters are reconciled rather than cascade-deleted.
@TableIndex(name: 'idx_offline_chapter_manga', columns: {#mangaId})
// Device-state queries rerun on per-page writes; index them to avoid full library scans.
@TableIndex(name: 'idx_offline_chapter_device_state', columns: {#deviceState})
class OfflineChapters extends Table {
  IntColumn get id => integer()();
  IntColumn get mangaId => integer()();
  TextColumn get name => text()();
  // sourceOrder can change; never use it as a stable key.
  IntColumn get chapterIndex => integer()();
  RealColumn get chapterNumber => real().nullable()();
  TextColumn get scanlator => text().nullable()();
  // Server epoch-millisecond strings; null until the next down-sync.
  TextColumn get uploadDate => text().nullable()();
  TextColumn get fetchedAt => text().nullable()();
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

  /// Local progress awaiting upload.
  BoolColumn get progressDirty =>
      boolean().withDefault(const Constant(false))();

  /// Independent of progress so syncing either change preserves the other.
  BoolColumn get bookmarkDirty =>
      boolean().withDefault(const Constant(false))();

  /// Separate from position changes to avoid uploading a stale isRead.
  BoolColumn get readStateDirty =>
      boolean().withDefault(const Constant(false))();

  /// Selects the tracker-sync gate while [readStateDirty] is true.
  BoolColumn get readStateManual =>
      boolean().withDefault(const Constant(false))();

  /// Read state reflected in the stored manga unreadCount: shown = stored − Σ(isRead − syncedIsRead).
  /// Preserve during unsettled reads; only down-sync, aggregate alignment, or adoption may move it.
  /// A push acknowledgement alone must not retire the correction before the aggregate refreshes.
  BoolColumn get syncedIsRead => boolean().withDefault(const Constant(false))();

  /// Server last-read timestamp as an epoch-millisecond string.
  TextColumn get lastReadAt => text().nullable()();

  /// Persisted generation rejects background events from downloads deleted before a restart.
  IntColumn get downloadGeneration =>
      integer().withDefault(const Constant(0))();

  /// Persistent retry budget, reset only after serverIsDownloaded becomes true.
  IntColumn get serverFetchAttempts =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class OfflineCategories extends Table {
  BoolColumn get isDefaultCategory =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get autoAdd => boolean().withDefault(const Constant(false))();
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
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

/// Page order follows fetchChapterPages; paths are relative to the offline root.
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
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Intermediate builds may have added columns without advancing the recorded schema.
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
        // Preserve pending completed reads; dirty unread rows remain position-only.
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
        // The old boolean treated true as NSFW, so preserve that filtering behavior.
        if (await _hasColumn(offlineMangas, 'source_is_nsfw')) {
          await customStatement(
            "UPDATE offline_mangas SET source_content_warning = "
            "CASE WHEN source_is_nsfw THEN 'NSFW' ELSE 'SAFE' END "
            "WHERE source_content_warning IS NULL",
          );
        }
      }
      // Divergent development schemas shared version numbers; inspect columns before adding or backfilling.
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
      if (from < 14) {
        // onCreate does not run during upgrades.
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
      if (from < 17 && await _hasTable(offlineCategories)) {
        await _addColumnIfMissing(
          m,
          offlineCategories,
          offlineCategories.isDefaultCategory,
        );
        await _addColumnIfMissing(
          m,
          offlineCategories,
          offlineCategories.autoAdd,
        );
        await customStatement(
          'UPDATE offline_categories SET is_default_category = 1 WHERE id = 0',
        );
      }
      if (from < 16) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.serverFetchAttempts,
        );
      }
      // Do not backfill '0': it can mean a valid server timestamp or an old removal.

      if (from < 18 && await _hasTable(offlineMangas)) {
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.chapterSortMode,
        );
      }
      if (from < 18 && await _hasTable(offlineChapters)) {
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.uploadDate,
        );
        await _addColumnIfMissing(
          m,
          offlineChapters,
          offlineChapters.fetchedAt,
        );
      }
      if (from < 19 && await _hasTable(offlineMangas)) {
        await _addColumnIfMissing(
          m,
          offlineMangas,
          offlineMangas.thumbnailUrlLastFetched,
        );
      }
    },
    beforeOpen: (details) async {
      if (!details.wasCreated) await _addMissingColumns();
    },
  );

  // Replay column backfills when _addMissingColumns supplies a skipped migration.
  late final Map<GeneratedColumn, String> _backfillAfterAdd = {
    offlineCategories.isDefaultCategory:
        'UPDATE offline_categories SET is_default_category = 1 WHERE id = 0',
    offlineChapters.syncedIsRead:
        'UPDATE offline_chapters SET synced_is_read = is_read',
  };

  // Divergent builds can share a schema version; heal missing nullable/defaulted columns on open.
  Future<void> _addMissingColumns() async {
    final columnsByTable = <String, Set<String>>{};
    for (final row in await customSelect(
      'SELECT m.name AS tbl, c.name AS col FROM sqlite_master m '
      "JOIN pragma_table_info(m.name) c WHERE m.type = 'table'",
    ).get()) {
      columnsByTable
          .putIfAbsent(row.read<String>('tbl'), () => {})
          .add(row.read<String>('col'));
    }
    Migrator? migrator;
    for (final table in allTables) {
      final existing = columnsByTable[table.actualTableName];
      // Missing tables belong to onUpgrade.
      if (existing == null) continue;
      for (final column in table.$columns) {
        if (existing.contains(column.name)) continue;
        if (!column.$nullable && column.defaultValue == null) {
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-db: '
            'missing-column-not-healable ${table.actualTableName}.${column.name}\n',
          );
          continue;
        }
        await (migrator ??= createMigrator()).addColumn(table, column);
        final backfill = _backfillAfterAdd[column];
        if (backfill != null) await customStatement(backfill);
        recordDiagnostic(
          '[${DateTime.now().toIso8601String()}] offline-db: '
          'healed-missing-column ${table.actualTableName}.${column.name}\n',
        );
      }
    }
  }

  // Partial upgrades may lack the table entirely; column checks alone cannot guard migration steps.
  Future<bool> _hasTable(TableInfo table) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      variables: [Variable<String>(table.actualTableName)],
    ).get();
    return rows.isNotEmpty;
  }

  // Intermediate builds can leave indexes present at an older recorded schema version.
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

  // addColumn throws when an intermediate build has already created the column.
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

  // Metadata refreshes must preserve device-managed columns.

  Future<void> upsertMangaMetadata({
    required int id,
    required String title,
    String? thumbnailUrl,
    String? thumbnailUrlLastFetched,
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
    ChapterSortAxis? chapterSortMode,
  }) => into(offlineMangas).insertOnConflictUpdate(
    OfflineMangasCompanion(
      id: Value(id),
      title: Value(title),
      updatedAt: Value(updatedAt),
      thumbnailUrl: thumbnailUrl == null
          ? const Value.absent()
          : Value(thumbnailUrl),
      thumbnailUrlLastFetched: thumbnailUrlLastFetched == null
          ? const Value.absent()
          : Value(thumbnailUrlLastFetched),
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
      // '0'/null means no signal; echoed offline DTOs must not erase timestamps.
      lastReadAt: (lastReadAt == null || lastReadAt == '0')
          ? const Value.absent()
          : Value(lastReadAt),
      metaJson: Value(metaJson),
      totalChapters: Value(totalChapters),
      // Absent server meta must clear the cached sort mode.
      chapterSortMode: Value(chapterSortMode),
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
    String? uploadDate,
    String? fetchedAt,
    // Server baseline, even when isRead preserves a pending local change.
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
      // Partial callers must not erase values supplied by a full sync.
      chapterNumber: chapterNumber == null
          ? const Value.absent()
          : Value(chapterNumber),
      scanlator: scanlator == null ? const Value.absent() : Value(scanlator),
      // '0'/null means no signal, as with lastReadAt.
      uploadDate: (uploadDate == null || uploadDate == '0')
          ? const Value.absent()
          : Value(uploadDate),
      fetchedAt: (fetchedAt == null || fetchedAt == '0')
          ? const Value.absent()
          : Value(fetchedAt),
      isRead: Value(isRead),
      lastPageRead: Value(lastPageRead),
      isBookmarked: Value(isBookmarked),
      serverIsDownloaded: Value(serverIsDownloaded),
      pageCount: Value(pageCount),
      updatedAt: Value(updatedAt),
      // '0'/null must not erase a stored timestamp.
      lastReadAt: (lastReadAt == null || lastReadAt == '0')
          ? const Value.absent()
          : Value(lastReadAt),
    ),
  );

  Future<void> upsertCategory(
    int id,
    String name,
    int sortOrder, {
    required bool isHidden,
    bool? isDefaultCategory,
    bool autoAdd = false,
  }) => into(offlineCategories).insertOnConflictUpdate(
    OfflineCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      isHidden: Value(isHidden),
      isDefaultCategory: Value(isDefaultCategory ?? id == 0),
      autoAdd: Value(autoAdd),
    ),
  );

  /// Local override until the next category sync; false if no mirrored row matched.
  Future<bool> setCategoryHidden(int id, bool hidden) async {
    final rows =
        await (update(offlineCategories)..where((t) => t.id.equals(id))).write(
          OfflineCategoriesCompanion(isHidden: Value(hidden)),
        );
    return rows > 0;
  }

  /// [serverIds] must come from a successful fetch; never prune after a failed fetch.
  Future<void> pruneRemovedCategories(Set<int> serverIds) =>
      transaction(() async {
        await (delete(
          offlineMangaCategories,
        )..where((t) => t.categoryId.isNotIn(serverIds))).go();
        await (delete(
          offlineCategories,
        )..where((t) => t.id.isNotIn(serverIds))).go();
      });

  /// Counts only memberships within [mangaIds].
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

  Future<Map<int, int>> chapterCountByManga() async {
    final mangaId = offlineChapters.mangaId;
    final chapterCount = offlineChapters.id.count();
    final query = selectOnly(offlineChapters)
      ..addColumns([mangaId, chapterCount])
      ..groupBy([mangaId]);
    final counts = <int, int>{};
    for (final row in await query.get()) {
      counts[row.read(mangaId)!] = row.read(chapterCount) ?? 0;
    }
    return counts;
  }

  /// Membership in a missing category counts as uncategorized.
  Future<Set<int>> uncategorizedOf(Set<int> mangaIds) async {
    if (mangaIds.isEmpty) return {};
    final rows = await (select(offlineMangaCategories).join([
      innerJoin(
        offlineCategories,
        offlineCategories.id.equalsExp(offlineMangaCategories.categoryId),
      ),
    ])..where(offlineMangaCategories.mangaId.isIn(mangaIds))).get();
    final categorized = {
      for (final row in rows) row.readTable(offlineMangaCategories).mangaId,
    };
    return mangaIds.difference(categorized);
  }

  /// Replaces memberships atomically; an empty list removes them all.
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

  /// Manga absent from the result have no stored categories.
  Future<Map<int, List<OfflineCategory>>> categoriesForMangas(
    Set<int> mangaIds,
  ) async {
    if (mangaIds.isEmpty) return {};
    final query =
        select(offlineMangaCategories).join([
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
      byManga
          .putIfAbsent(mangaId, () => [])
          .add(row.readTable(offlineCategories));
    }
    return byManga;
  }

  Future<List<OfflineCategory>> allOfflineCategories() => (select(
    offlineCategories,
  )..orderBy([(t) => OrderingTerm(expression: t.sortOrder)])).get();


  Future<void> setMangaCoverPath(int mangaId, String relPath) =>
      (update(offlineMangas)..where((t) => t.id.equals(mangaId))).write(
        OfflineMangasCompanion(thumbnailRelPath: Value(relPath)),
      );

  Future<void> updateMangaMetaValue({
    required int mangaId,
    required String key,
    String? value,
  }) async {
    final row = await mangaById(mangaId);
    if (row == null) return;
    // Mirror the sync writer's encoding so offline-first reads see the edit.
    final meta = <String, String>{};
    final raw = row.metaJson;
    if (raw != null && raw.isNotEmpty) {
      try {
        meta.addAll(Map<String, String>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    if (value == null) {
      meta.remove(key);
    } else {
      meta[key] = value;
    }
    await (update(offlineMangas)..where((t) => t.id.equals(mangaId))).write(
      OfflineMangasCompanion(metaJson: Value(jsonEncode(meta))),
    );
  }

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

  Future<void> incrementServerFetchAttempts(int chapterId) => customUpdate(
    'UPDATE offline_chapters SET server_fetch_attempts = server_fetch_attempts + 1 '
    'WHERE id = ?',
    variables: [Variable<int>(chapterId)],
    updates: {offlineChapters},
  );

  Future<void> resetServerFetchAttempts(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        const OfflineChaptersCompanion(serverFetchAttempts: Value(0)),
      );

  /// Records transferred pages atomically; [clearSourceChapterId] also resets the source in that transaction.
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
      await bumpChapterGeneration(clearSourceChapterId);
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

  /// After staging promotion, records pages and downloaded state atomically.
  /// [pageCount] describes the committed copy rather than the server value.
  Future<void> commitDownloadedChapter({
    required int chapterId,
    required List<({int pageIndex, String relPath, int bytes})> pages,
    required DateTime downloadedAt,
  }) async {
    // Empty page rows would claim a local download while forcing the reader to stream.
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

  Future<void> unpinChaptersForManga(int mangaId) =>
      (update(offlineChapters)..where((t) => t.mangaId.equals(mangaId))).write(
        const OfflineChaptersCompanion(pinned: Value(false)),
      );

  /// Call on every delete to reject older in-flight events, including across restarts.
  Future<int> bumpChapterGeneration(int chapterId) => transaction(() async {
    final current = await chapterById(chapterId);
    final next = (current?.downloadGeneration ?? 0) + 1;
    await (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
      OfflineChaptersCompanion(downloadGeneration: Value(next)),
    );
    return next;
  });

  /// Records pending progress; [manual] selects the tracker gate when [isRead] is supplied.
  Future<void> setChapterProgress(
    int chapterId, {
    required int lastPageRead,
    bool? isRead,
    bool manual = false,
  }) => (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
    OfflineChaptersCompanion(
      lastPageRead: Value(lastPageRead),
      progressDirty: const Value(true),
      // Local epoch seconds supply the Last Read sort until down-sync.
      lastReadAt: Value(_nowEpochSeconds()),
      // Null leaves read state untouched; position-only writes must not upload stale isRead.
      isRead: isRead == null ? const Value.absent() : Value(isRead),
      readStateDirty: isRead == null ? const Value.absent() : const Value(true),
      readStateManual: isRead == null ? const Value.absent() : Value(manual),
    ),
  );

  static String _nowEpochSeconds() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  /// Records pending read state without changing position; [manual] selects the tracker gate.
  Future<void> setChapterReadState(
    int chapterId,
    bool isRead, {
    bool manual = true,
  }) => (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
    OfflineChaptersCompanion(
      isRead: Value(isRead),
      readStateDirty: const Value(true),
      readStateManual: Value(manual),
      // Marking unread is bookkeeping, not new reading activity.
      lastReadAt: isRead ? Value(_nowEpochSeconds()) : const Value.absent(),
    ),
  );

  /// Local unread-count correction measured against [OfflineChapters.syncedIsRead].
  Future<Map<int, int>> unsyncedReadDeltaByManga() async {
    final rows = await (select(
      offlineChapters,
    )..where((t) => t.isRead.equalsExp(t.syncedIsRead).not())).get();
    final delta = <int, int>{};
    for (final r in rows) {
      delta[r.mangaId] = (delta[r.mangaId] ?? 0) + (r.isRead ? 1 : -1);
    }
    return delta;
  }

  Future<void> clearProgressDirty(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        const OfflineChaptersCompanion(progressDirty: Value(false)),
      );

  Future<void> clearBookmarkDirty(int chapterId) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        const OfflineChaptersCompanion(bookmarkDirty: Value(false)),
      );

  /// Clears only the pushed snapshot; concurrent local edits remain dirty.
  Future<void> clearProgressDirtyIfUnchanged(
    int chapterId, {
    required int lastPageRead,
  }) =>
      (update(offlineChapters)..where(
            (t) => t.id.equals(chapterId) & t.lastPageRead.equals(lastPageRead),
          ))
          .write(const OfflineChaptersCompanion(progressDirty: Value(false)));

  // Order acknowledgements against aggregate fetches within this session.
  int _pushGen = 0;
  final Map<int, int> _ackGen = {};

  /// Capture before starting the aggregate fetch so later acknowledgements stay unaligned.
  int get syncGeneration => _pushGen;

  /// Clears only if isRead still matches the pushed snapshot.
  Future<void> clearReadStateDirtyIfUnchanged(
    int chapterId, {
    required bool isRead,
  }) async {
    final matched =
        await (update(offlineChapters)
              ..where((t) => t.id.equals(chapterId) & t.isRead.equals(isRead)))
            .write(
              // Keep the baseline until the stored unread aggregate includes this acknowledgement.
              const OfflineChaptersCompanion(readStateDirty: Value(false)),
            );
    // A concurrent local edit must re-acknowledge on a later pass.
    if (matched > 0) _ackGen[chapterId] = ++_pushGen;
  }

  /// Retires corrections only for clean rows acknowledged before [upToGen].
  /// Capture [upToGen] before fetching the aggregate; returns corrections needing a later fetch.
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

  /// Chunked to stay within SQLite's bound-variable limit.
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

  /// Adopts server state only if the examined local values still match; clears its correction too.
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

  /// Clears only if the bookmark still matches the pushed snapshot.
  Future<void> clearBookmarkDirtyIfUnchanged(
    int chapterId, {
    required bool isBookmarked,
  }) =>
      (update(offlineChapters)..where(
            (t) => t.id.equals(chapterId) & t.isBookmarked.equals(isBookmarked),
          ))
          .write(const OfflineChaptersCompanion(bookmarkDirty: Value(false)));

  /// Marks bookmarks independently so syncing them cannot upload stale reading progress.
  Future<void> setChapterBookmark(int chapterId, bool isBookmarked) =>
      (update(offlineChapters)..where((t) => t.id.equals(chapterId))).write(
        OfflineChaptersCompanion(
          isBookmarked: Value(isBookmarked),
          bookmarkDirty: const Value(true),
        ),
      );

  Future<List<OfflineChapter>> dirtyProgressChapters() => (select(
    offlineChapters,
  )..where((t) => t.progressDirty.equals(true))).get();

  /// Includes progress, read-state, and bookmark changes.
  Future<List<OfflineChapter>> dirtyChapters() =>
      (select(offlineChapters)..where(
            (t) =>
                t.progressDirty.equals(true) |
                t.bookmarkDirty.equals(true) |
                t.readStateDirty.equals(true),
          ))
          .get();


  Future<OfflineManga?> mangaById(int mangaId) => (select(
    offlineMangas,
  )..where((t) => t.id.equals(mangaId))).getSingleOrNull();

  Future<OfflineChapter?> chapterById(int chapterId) => (select(
    offlineChapters,
  )..where((t) => t.id.equals(chapterId))).getSingleOrNull();

  Future<List<OfflineManga>> libraryManga() =>
      (select(offlineMangas)
            // Removed manga can retain downloads but must stay hidden from the library.
            ..where(
              (t) =>
                  t.inLibraryAt.equals(kLibraryRemovedSentinel).not() |
                  t.inLibraryAt.isNull(),
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

  /// Restore only sentinel rows using a complete library fetch, before [markNotInLibrary].
  Future<void> restoreLibraryTimestamps(
    Map<int, String> inLibraryAtById,
  ) async {
    if (inLibraryAtById.isNotEmpty) {
      final ids = inLibraryAtById.keys.toSet();
      final sentinelRows =
          await (select(offlineMangas)..where(
                (t) =>
                    t.id.isIn(ids) &
                    t.inLibraryAt.equals(kLibraryRemovedSentinel),
              ))
              .get();
      if (sentinelRows.isNotEmpty) {
        final restored = <int>[];
        final serverSentSentinel = <int>[];
        for (final row in sentinelRows) {
          final serverValue = inLibraryAtById[row.id];
          if (serverValue == kLibraryRemovedSentinel) {
            serverSentSentinel.add(row.id);
          } else {
            restored.add(row.id);
          }
        }
        if (restored.isNotEmpty) {
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-sync: '
            'restore-library-timestamp mangaIds(${restored.length})='
            '[${restored.join(',')}]\n',
          );
        }
        if (serverSentSentinel.isNotEmpty) {
          recordDiagnostic(
            '[${DateTime.now().toIso8601String()}] offline-sync: '
            'server-sent-removal-sentinel '
            'mangaIds(${serverSentSentinel.length})='
            '[${serverSentSentinel.join(',')}]\n',
          );
        }
      }
    }
    await batch((b) {
      for (final entry in inLibraryAtById.entries) {
        b.update(
          offlineMangas,
          OfflineMangasCompanion(inLibraryAt: Value(entry.value)),
          where: (t) =>
              t.id.equals(entry.key) &
              t.inLibraryAt.equals(kLibraryRemovedSentinel),
        );
      }
    });
  }

  /// [libraryIds] must be a complete successful fetch; absent ids are marked removed.
  /// NULL timestamps still count as library entries.
  Future<int> markNotInLibrary(Set<int> libraryIds) async {
    final candidates = await (select(
      offlineMangas,
    )..where((t) => t.id.isNotIn(libraryIds))).get();
    final nullToRemoved = <int>[];
    final realToRemoved = <int>[];
    var alreadyRemoved = 0;
    for (final row in candidates) {
      final v = row.inLibraryAt;
      if (v == null) {
        nullToRemoved.add(row.id);
      } else if (v == kLibraryRemovedSentinel) {
        alreadyRemoved++;
      } else {
        realToRemoved.add(row.id);
      }
    }
    if (nullToRemoved.isNotEmpty || realToRemoved.isNotEmpty) {
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-sync: '
        'mark-not-in-library libraryCount=${libraryIds.length} '
        'nullToRemoved(${nullToRemoved.length})=[${nullToRemoved.join(',')}] '
        'realToRemoved(${realToRemoved.length})=[${realToRemoved.join(',')}] '
        'alreadyRemoved=$alreadyRemoved\n',
      );
    }
    return (update(
      offlineMangas,
    )..where((t) => t.id.isNotIn(libraryIds))).write(
      const OfflineMangasCompanion(inLibraryAt: Value(kLibraryRemovedSentinel)),
    );
  }

  Future<void> logLibraryStampCounters(String label) async {
    final rows = await select(offlineMangas).get();
    var real = 0;
    var nullCount = 0;
    var zero = 0;
    var removed = 0;
    for (final row in rows) {
      final v = row.inLibraryAt;
      if (v == null) {
        nullCount++;
      } else if (v == kLibraryRemovedSentinel) {
        removed++;
      } else if (v == '0') {
        zero++;
      } else {
        real++;
      }
    }
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-sync: '
      'library-stamp-counters($label) total=${rows.length} real=$real '
      'null=$nullCount zero=$zero removed=$removed\n',
    );
  }

  /// Purges only sentinel rows, preserving legacy NULL rows during concurrent metadata upserts.
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
                offlineMangas.inLibraryAt.equals(kLibraryRemovedSentinel) &
                    offlineMangas.id.isNotInQuery(withDeviceContent),
              ))
            .map((r) => r.read(offlineMangas.id)!)
            .get();

    final withDeviceContentAgain = selectOnly(offlineChapters)
      ..addColumns([offlineChapters.mangaId])
      ..where(
        offlineChapters.deviceState.equalsValue(OfflineDeviceState.none).not(),
      );
    final stranded =
        await (selectOnly(offlineMangas)
              ..addColumns([offlineMangas.id])
              ..where(
                offlineMangas.inLibraryAt.equals(kLibraryRemovedSentinel) &
                    offlineMangas.id.isInQuery(withDeviceContentAgain),
              ))
            .map((r) => r.read(offlineMangas.id)!)
            .get();
    if (stranded.isNotEmpty) {
      recordDiagnostic(
        '[${DateTime.now().toIso8601String()}] offline-sync: '
        'stranded-removed-stamp-with-downloads '
        'mangaIds=[${stranded.join(',')}] — hidden from the offline library '
        '(inLibraryAt=$kLibraryRemovedSentinel) but kept on device because '
        'they still have downloaded content; if a manga lingers here across '
        'syncs, the last complete library fetch did not carry that id at '
        'all (see restore-library-timestamp lines above)\n',
      );
    }

    if (doomed.isEmpty) return 0;
    recordDiagnostic(
      '[${DateTime.now().toIso8601String()}] offline-sync: '
      'purge-removed-library-manga mangaIds=[${doomed.join(',')}]\n',
    );
    // These rows have no device content; sweep their metadata children because there is no cascading foreign key.
    await (delete(offlineChapters)..where((t) => t.mangaId.isIn(doomed))).go();
    await (delete(
      offlineMangaCategories,
    )..where((t) => t.mangaId.isIn(doomed))).go();
    return (delete(offlineMangas)..where((t) => t.id.isIn(doomed))).go();
  });

  /// Purges non-library metadata only when no device content remains.
  Future<int> purgeNonLibraryManga() {
    final withDeviceContent = selectOnly(offlineChapters)
      ..addColumns([offlineChapters.mangaId])
      ..where(
        offlineChapters.deviceState.equalsValue(OfflineDeviceState.none).not(),
      );
    return (delete(offlineMangas)..where(
          (t) =>
              (t.inLibraryAt.isNull() |
                  t.inLibraryAt.equals(kLibraryRemovedSentinel)) &
              t.id.isNotInQuery(withDeviceContent),
        ))
        .go();
  }

  /// Timestamps are epoch-second strings; compare numerically.
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

  /// Omits manga without an unread downloaded chapter.
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
      result.putIfAbsent(c.mangaId, () => c);
    }
    return result;
  }

  Future<List<OfflineChapter>> chaptersForManga(int mangaId) =>
      (select(offlineChapters)
            ..where((t) => t.mangaId.equals(mangaId))
            ..orderBy([(t) => OrderingTerm(expression: t.chapterIndex)]))
          .get();

  Future<void> markChaptersOrphaned(List<int> chapterIds) =>
      (update(offlineChapters)..where((t) => t.id.isIn(chapterIds))).write(
        const OfflineChaptersCompanion(
          deviceState: Value(OfflineDeviceState.orphaned),
        ),
      );

  /// Rechecks device state so chapters queued during the fetch remain with the download worker.
  Future<int> deleteGoneChapters(List<int> chapterIds) =>
      (delete(offlineChapters)..where(
            (t) =>
                t.id.isIn(chapterIds) &
                t.deviceState.isIn([
                  OfflineDeviceState.none.name,
                  OfflineDeviceState.error.name,
                ]),
          ))
          .go();

  Stream<List<OfflineChapter>> watchChaptersForManga(int mangaId) => (select(
    offlineChapters,
  )..where((t) => t.mangaId.equals(mangaId))).watch();

  /// Includes queued and downloading chapters as well as completed downloads.
  Stream<List<OfflineChapter>> watchOfflineChapters() =>
      (select(offlineChapters)..where(
            (t) => t.deviceState.isIn([
              OfflineDeviceState.downloaded.name,
              OfflineDeviceState.downloading.name,
              OfflineDeviceState.queued.name,
            ]),
          ))
          .watch();

  /// Includes series with device content or an active keep-rule, even before its first download.
  Stream<
    List<
      ({
        OfflineManga manga,
        int downloaded,
        int inFlight,
        int failed,
        int bytes,
      })
    >
  >
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
    final failed = offlineChapters.id.count(
      filter: offlineChapters.deviceState.equalsValue(OfflineDeviceState.error),
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
          ..addColumns([downloaded, inFlight, failed, byteSum])
          ..groupBy(
            [offlineMangas.id],
            having:
                downloaded.isBiggerThanValue(0) |
                inFlight.isBiggerThanValue(0) |
                failed.isBiggerThanValue(0) |
                offlineMangas.keepRule.equalsValue(OfflineKeepRule.off).not(),
          );
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          (
            manga: row.readTable(offlineMangas),
            downloaded: row.read(downloaded) ?? 0,
            inFlight: row.read(inFlight) ?? 0,
            failed: row.read(failed) ?? 0,
            bytes: row.read(byteSum) ?? 0,
          ),
      ],
    );
  }

  Future<int> downloadedPageCount(int chapterId) async {
    final cnt = offlinePages.pageIndex.count();
    final row =
        await (selectOnly(offlinePages)
              ..addColumns([cnt])
              ..where(offlinePages.chapterId.equals(chapterId)))
            .getSingle();
    return row.read(cnt) ?? 0;
  }

  /// Ordered by manga then chapter.
  Future<List<OfflineChapter>> chaptersInState(OfflineDeviceState state) =>
      (select(offlineChapters)
            ..where((t) => t.deviceState.equalsValue(state))
            ..orderBy([
              (t) => OrderingTerm(expression: t.mangaId),
              (t) => OrderingTerm(expression: t.chapterIndex),
            ]))
          .get();

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

  Stream<Set<int>> watchMangaIdsWithDeviceDownloads() {
    final query = selectOnly(offlineChapters, distinct: true)
      ..addColumns([offlineChapters.mangaId])
      ..where(
        offlineChapters.deviceState.equalsValue(OfflineDeviceState.downloaded),
      );
    return query.watch().map(
      (rows) => {for (final r in rows) r.read(offlineChapters.mangaId)!},
    );
  }

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

  Future<int> downloadedBytesForManga(int mangaId) async {
    final sum = offlineChapters.bytes.sum();
    final row =
        await (selectOnly(offlineChapters)
              ..addColumns([sum])
              ..where(
                offlineChapters.mangaId.equals(mangaId) &
                    offlineChapters.deviceState.equalsValue(
                      OfflineDeviceState.downloaded,
                    ),
              ))
            .getSingle();
    return row.read(sum) ?? 0;
  }
}
