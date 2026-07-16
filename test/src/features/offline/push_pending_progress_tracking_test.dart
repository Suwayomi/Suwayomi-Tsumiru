// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/tracking/controller/manga_track_records_controller.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/domain/tracking_settings_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:hooks_riverpod/misc.dart';

import '../../../helpers/offline_test_db.dart';

// ---------------------------------------------------------------------------
// Stub implementations
// ---------------------------------------------------------------------------

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

/// Records trackProgress calls without touching a real GraphQL server.
class _FakeTrackerRepository extends TrackerRepository {
  _FakeTrackerRepository() : super(_dummyClient());

  final List<int> trackProgressCalls = [];

  @override
  Future<void> trackProgress(int mangaId) async {
    trackProgressCalls.add(mangaId);
  }

  @override
  Future<List<Fragment$TrackRecordDto>?> getMangaTrackRecords(int mangaId) =>
      Future.value(const []);
}

/// Stubs putChapter so tests don't need a live GraphQL server.
class _FakeMangaBookRepository extends MangaBookRepository {
  _FakeMangaBookRepository() : super(_dummyClient());

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    // Always succeeds so clearProgressDirty is called.
  }
}

/// Captures every pushed patch so a test can assert exactly which fields the
/// up-sync sent (the ch-99 fix: a position-dirty row must push no isRead).
class _CapturingMangaBookRepository extends MangaBookRepository {
  _CapturingMangaBookRepository() : super(_dummyClient());

  final List<ChapterChange> patches = [];

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    patches.add(patch);
  }
}

/// putChapter that fails like an offline mutation — used to prove a failed push
/// keeps the dirty flag (the bug where offline progress/bookmarks were cleared
/// without ever reaching the server).
class _FailingMangaBookRepository extends MangaBookRepository {
  _FailingMangaBookRepository() : super(_dummyClient());

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    throw Exception('offline — mutation failed');
  }
}

/// Notifier subclass that returns a fixed bool? without touching SharedPreferences.
class _FixedToggle extends UpdateProgressAfterReading {
  _FixedToggle(this._value);
  final bool _value;

  @override
  bool? build() => _value;
}

// ---------------------------------------------------------------------------
// Helper: seed a chapter row (optionally dirty)
// ---------------------------------------------------------------------------

Future<void> _seed(
  OfflineDatabase db,
  int id, {
  required int mangaId,
  bool isRead = false,
  bool dirty = false,
}) async {
  await db.upsertChapterMetadata(
    id: id,
    mangaId: mangaId,
    name: 'c$id',
    chapterIndex: id,
    isRead: isRead,
    lastPageRead: 0,
    isBookmarked: false,
    serverIsDownloaded: true,
    pageCount: 10,
    updatedAt: DateTime(2026),
  );
  if (dirty) {
    await db.setChapterProgress(id, lastPageRead: 0, isRead: isRead);
  }
}

// ---------------------------------------------------------------------------
// Helper: build a ProviderContainer wired with fakes
// ---------------------------------------------------------------------------

/// One fake track-record stub (the test only cares about .length, not content).
Fragment$TrackRecordDto _fakeRecord() => Fragment$TrackRecordDto(
      id: 99,
      trackerId: 1,
      remoteId: 'remote-1',
      title: 'Manga',
      remoteUrl: 'https://example.com',
      status: 1,
      lastChapterRead: 0,
      totalChapters: 0,
      score: 0,
      displayScore: '0',
      startDate: '',
      finishDate: '',
      private: false,
    );

Future<
    ({
      ProviderContainer container,
      OfflineDatabase db,
      _FakeTrackerRepository tracker,
    })> _build({
  required List<int> mangaIds,
  int trackRecordCount = 1,
  bool toggleOn = true,
  MangaBookRepository? repository,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = testOfflineDatabase();
  final fakeTracker = _FakeTrackerRepository();
  final fakeMangaBook = repository ?? _FakeMangaBookRepository();

  final records = List.generate(trackRecordCount, (_) => _fakeRecord());

  final overrides = <Override>[
    sharedPreferencesProvider.overrideWithValue(prefs),
    offlineEnabledProvider.overrideWithValue(true),
    offlineActiveProvider.overrideWithValue(true),
    offlineDatabaseProvider.overrideWithValue(db),
    mangaBookRepositoryProvider.overrideWithValue(fakeMangaBook),
    trackerRepositoryProvider.overrideWithValue(fakeTracker),
    updateProgressAfterReadingProvider
        .overrideWith(() => _FixedToggle(toggleOn)),
    for (final id in mangaIds)
      mangaTrackRecordsProvider(mangaId: id)
          .overrideWith((_) => Future.value(records)),
  ];

  final container = ProviderContainer(overrides: overrides);

  return (container: container, db: db, tracker: fakeTracker);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('pushPendingProgress → tracker push', () {
    test('toggle ON + manga has track records → trackProgress called once',
        () async {
      final (:container, :db, :tracker) = await _build(
        mangaIds: [1],
        trackRecordCount: 1,
        toggleOn: true,
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      await _seed(db, 10, mangaId: 1, isRead: true, dirty: true);

      await pushPendingProgress(container);

      expect(tracker.trackProgressCalls, [1],
          reason: 'trackProgress must fire once for manga 1');
    });

    test('toggle OFF → trackProgress NOT called', () async {
      final (:container, :db, :tracker) = await _build(
        mangaIds: [1],
        trackRecordCount: 1,
        toggleOn: false,
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      await _seed(db, 10, mangaId: 1, isRead: true, dirty: true);

      await pushPendingProgress(container);

      expect(tracker.trackProgressCalls, isEmpty,
          reason: 'toggle is off — no tracker push');
    });

    test(
        'failed push KEEPS the dirty flag (stays pending, server never got it)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = testOfflineDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineEnabledProvider.overrideWithValue(true),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        mangaBookRepositoryProvider
            .overrideWithValue(_FailingMangaBookRepository()),
      ]);
      addTearDown(container.dispose);

      await _seed(db, 10, mangaId: 1, isRead: true, dirty: true);

      await pushPendingProgress(container);

      // The push threw → the chapter must remain dirty so it retries later,
      // instead of being silently marked synced.
      expect((await db.dirtyProgressChapters()).map((c) => c.id), [10],
          reason: 'a failed push must not clear the dirty flag');
    });

    test('zero track records → trackProgress NOT called', () async {
      final (:container, :db, :tracker) = await _build(
        mangaIds: [1],
        trackRecordCount: 0,
        toggleOn: true,
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      await _seed(db, 10, mangaId: 1, isRead: true, dirty: true);

      await pushPendingProgress(container);

      expect(tracker.trackProgressCalls, isEmpty,
          reason: 'no tracker bound — gate must reject');
    });

    test(
        'toggle ON + multiple chapters for same manga → trackProgress called only ONCE',
        () async {
      final (:container, :db, :tracker) = await _build(
        mangaIds: [1],
        trackRecordCount: 1,
        toggleOn: true,
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      // Three read+dirty chapters all for manga 1.
      await _seed(db, 10, mangaId: 1, isRead: true, dirty: true);
      await _seed(db, 11, mangaId: 1, isRead: true, dirty: true);
      await _seed(db, 12, mangaId: 1, isRead: true, dirty: true);

      await pushPendingProgress(container);

      expect(tracker.trackProgressCalls.length, 1,
          reason: 'deduplication: only one trackProgress call per manga');
      expect(tracker.trackProgressCalls.first, 1);
    });

    test('chapters with isRead=false do NOT trigger tracker push', () async {
      final (:container, :db, :tracker) = await _build(
        mangaIds: [1],
        trackRecordCount: 1,
        toggleOn: true,
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      // Dirty progress update but chapter is not finished.
      await _seed(db, 10, mangaId: 1, isRead: false, dirty: true);

      await pushPendingProgress(container);

      expect(tracker.trackProgressCalls, isEmpty,
          reason: 'isRead=false chapters must not trigger tracker');
    });
  });

  group('pushPendingProgress → per-field push', () {
    test('position-dirty row never pushes isRead (ch-99 revert)', () async {
      final repo = _CapturingMangaBookRepository();
      final (:container, :db, :tracker) =
          await _build(mangaIds: [1], repository: repo);
      addTearDown(() {
        container.dispose();
        db.close();
      });

      await _seed(db, 10, mangaId: 1); // clean row
      await db.setChapterProgress(10, lastPageRead: 5, isRead: null); // partial

      await pushPendingProgress(container);

      expect(repo.patches.single.lastPageRead, 5);
      expect(repo.patches.single.isRead, isNull); // THE fix
      expect((await db.chapterById(10))!.progressDirty, isFalse);
    });

    test('read-state-dirty row pushes isRead and clears its flag', () async {
      final repo = _CapturingMangaBookRepository();
      final (:container, :db, :tracker) =
          await _build(mangaIds: [1], repository: repo);
      addTearDown(() {
        container.dispose();
        db.close();
      });

      await _seed(db, 10, mangaId: 1);
      await db.setChapterReadState(10, true);

      await pushPendingProgress(container);

      expect(repo.patches.single.isRead, isTrue);
      expect((await db.chapterById(10))!.readStateDirty, isFalse);
    });

    // The full reported loop, end to end. Pre-fix this reverted 100%: the
    // partial read left the row position-dirty with isRead=false, list
    // mark-read never touched the local row, and the reconnect push sent that
    // stale isRead=false — reverting the chapter to unread on the server.
    test('ch-99 loop is dead: offline partial-read then mark-read syncs '
        'read=true, never a stale unread', () async {
      final repo = _CapturingMangaBookRepository();
      final (:container, :db, :tracker) =
          await _build(mangaIds: [1], repository: repo);
      addTearDown(() {
        container.dispose();
        db.close();
      });

      await _seed(db, 99, mangaId: 1);
      // Offline partial read of ch 99 (back out): records position only.
      await recordReadingProgressWithDependencies(
        offlineEnabled: true,
        offlineDatabase: db,
        repository: _FailingMangaBookRepository(),
        chapterId: 99,
        lastPageRead: 5,
        isRead: false,
      );
      // Offline mark-read from the list: write-through updates the local row.
      await recordReadStateWithDependencies(
        offlineEnabled: true,
        offlineDatabase: db,
        repository: _FailingMangaBookRepository(),
        chapterIds: [99],
        isRead: true,
        resetPosition: true,
      );

      // Reconnect and flush.
      await pushPendingProgress(container);

      final patch = repo.patches.single;
      expect(patch.isRead, isTrue,
          reason: 'the mark-read reaches the server (used to revert to unread)');
      expect(patch.lastPageRead, 0, reason: 'mark-read reset the position');
      final c = (await db.chapterById(99))!;
      expect(c.isRead, isTrue);
      expect(c.progressDirty, isFalse);
      expect(c.readStateDirty, isFalse);
    });
  });
}
