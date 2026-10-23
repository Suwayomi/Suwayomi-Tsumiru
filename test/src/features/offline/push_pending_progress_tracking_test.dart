// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/tracking/controller/manga_track_records_controller.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/domain/tracking_settings_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../helpers/offline_test_db.dart';

// ---------------------------------------------------------------------------
// Stub implementations
// ---------------------------------------------------------------------------

class _SessionStore extends AuthCredentialsStore {
  int epoch = 0;
  @override
  int get sessionEpoch => epoch;
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

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

/// Captures pushed patches AND returns a fixed server chapter from getChapter,
/// so the never-regress guard (cross-device) can be exercised.
class _ServerStateRepository extends MangaBookRepository {
  _ServerStateRepository(this._server) : super(_dummyClient());
  final ChapterDto _server;
  final List<ChapterChange> patches = [];

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    patches.add(patch);
  }

  @override
  Future<ChapterDto?> getChapter({required int chapterId}) async => _server;
}

ChapterDto _serverChapter({
  required int id,
  required bool isRead,
  required int lastPageRead,
  String lastReadAt = '0',
}) => ChapterDto(
  chapterNumber: id.toDouble(),
  fetchedAt: '0',
  id: id,
  mangaId: 1,
  name: 'c$id',
  pageCount: 10,
  sourceOrder: id,
  uploadDate: '0',
  url: 'u$id',
  meta: const [],
  user: Fragment$ChapterDto$user(
    isBookmarked: false,
    isDownloaded: true,
    isRead: isRead,
    lastPageRead: lastPageRead,
    lastReadAt: lastReadAt,
  ),
);

/// Notifier subclass that returns a fixed bool? without touching SharedPreferences.
class _FixedToggle extends UpdateProgressAfterReading {
  _FixedToggle(this._value);
  final bool _value;

  @override
  bool? build() => _value;
}

/// Same, for the manual-mark-read toggle.
class _FixedManualToggle extends UpdateProgressManualMarkRead {
  _FixedManualToggle(this._value);
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
  })
>
_build({
  required List<int> mangaIds,
  int trackRecordCount = 1,
  bool toggleOn = true,
  bool manualToggleOn = false,
  MangaBookRepository? repository,
  OfflineDatabase? database,
  _SessionStore? session,
  Future<List<Fragment$TrackRecordDto>> Function()? recordsLookup,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = database ?? testOfflineDatabase();
  final fakeTracker = _FakeTrackerRepository();
  final fakeMangaBook = repository ?? _FakeMangaBookRepository();

  final records = List.generate(trackRecordCount, (_) => _fakeRecord());

  final overrides = <Override>[
    authCredentialsStoreProvider.overrideWith(() => session ?? _SessionStore()),
    sharedPreferencesProvider.overrideWithValue(prefs),
    offlineEnabledProvider.overrideWithValue(true),
    offlineActiveProvider.overrideWithValue(true),
    offlineDatabaseProvider.overrideWithValue(db),
    mangaBookRepositoryProvider.overrideWithValue(fakeMangaBook),
    trackerRepositoryProvider.overrideWithValue(fakeTracker),
    updateProgressAfterReadingProvider.overrideWith(
      () => _FixedToggle(toggleOn),
    ),
    updateProgressManualMarkReadProvider.overrideWith(
      () => _FixedManualToggle(manualToggleOn),
    ),
    for (final id in mangaIds)
      mangaTrackRecordsProvider(
        mangaId: id,
      ).overrideWith((_) => recordsLookup?.call() ?? Future.value(records)),
  ];

  final container = ProviderContainer(overrides: overrides);

  return (container: container, db: db, tracker: fakeTracker);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Captures the patch a partial-read write sends; the never-un-read guard keeps
/// isRead out of it entirely.
class _PartialReadRepo extends MangaBookRepository {
  _PartialReadRepo() : super(_dummyClient());
  ChapterChange? lastPatch;
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    lastPatch = patch;
  }
}

void main() {
  test('failed push KEEPS the dirty flag (stays pending)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testOfflineDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineEnabledProvider.overrideWithValue(true),
        offlineActiveProvider.overrideWithValue(true),
        offlineDatabaseProvider.overrideWithValue(db),
        mangaBookRepositoryProvider.overrideWithValue(
          _FailingMangaBookRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _seed(db, 10, mangaId: 1, isRead: true, dirty: true);
    await pushPendingProgress(container);

    expect((await db.dirtyProgressChapters()).map((c) => c.id), [
      10,
    ], reason: 'a failed push must not clear the dirty flag');
  });

  test('a manual mark-read is gated on the MANUAL toggle, not the '
      'after-reading toggle', () async {
    // after-reading OFF, manual-mark-read ON: an offline manual mark-read
    // must still reach the tracker once reconnected.
    final first = await _build(
      mangaIds: [1],
      trackRecordCount: 1,
      toggleOn: false,
      manualToggleOn: true,
    );
    addTearDown(() {
      first.container.dispose();
      first.db.close();
    });
    await _seed(first.db, 10, mangaId: 1);
    await recordReadStateWithDependencies(
      offlineEnabled: true,
      offlineDatabase: first.db,
      repository: _FailingMangaBookRepository(),
      chapterIds: [10],
      isRead: true,
      resetPosition: true,
    );
    await pushPendingProgress(first.container);
    expect(
      first.tracker.trackProgressCalls,
      [1],
      reason: 'manual-mark-read toggle is ON; the after-reading toggle is OFF',
    );

    // Manual toggle OFF suppresses a manual action even with after-reading ON.
    final second = await _build(
      mangaIds: [1],
      trackRecordCount: 1,
      toggleOn: true,
      manualToggleOn: false,
    );
    addTearDown(() {
      second.container.dispose();
      second.db.close();
    });
    await _seed(second.db, 10, mangaId: 1);
    await recordReadStateWithDependencies(
      offlineEnabled: true,
      offlineDatabase: second.db,
      repository: _FailingMangaBookRepository(),
      chapterIds: [10],
      isRead: true,
      resetPosition: true,
    );
    await pushPendingProgress(second.container);
    expect(second.tracker.trackProgressCalls, isEmpty);
  });

  test('per-field push: position-dirty never sends isRead; read-state-dirty '
      'sends it and clears its flag', () async {
    final repo = _CapturingMangaBookRepository();
    final (:container, :db, :tracker) = await _build(
      mangaIds: [1],
      repository: repo,
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });

    await _seed(db, 10, mangaId: 1); // clean row
    await db.setChapterProgress(10, lastPageRead: 5, isRead: null);
    await pushPendingProgress(container);

    expect(repo.patches.single.lastPageRead, 5);
    expect(repo.patches.single.isRead, isNull, reason: 'ch-99 revert fix');
    expect((await db.chapterById(10))!.progressDirty, isFalse);

    await db.setChapterReadState(10, true);
    await pushPendingProgress(container);

    expect(repo.patches.length, 2);
    expect(repo.patches.last.isRead, isTrue);
    expect((await db.chapterById(10))!.readStateDirty, isFalse);
  });

  test(
    'cross-device never-regress and a partial read never un-reads',
    () async {
      final repo = _ServerStateRepository(
        _serverChapter(id: 10, isRead: false, lastPageRead: 3),
      );
      final (:container, :db, :tracker) = await _build(
        mangaIds: [1],
        repository: repo,
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      await _seed(db, 10, mangaId: 1);
      await db.setChapterProgress(10, lastPageRead: 8, isRead: null);
      await pushPendingProgress(container);

      expect(repo.patches.single.lastPageRead, 8);
      expect((await db.chapterById(10))!.progressDirty, isFalse);

      final partial = _PartialReadRepo();
      await recordReadingProgressWithDependencies(
        offlineEnabled: false,
        offlineDatabase: null,
        repository: partial,
        chapterId: 11,
        lastPageRead: 38,
        isRead: false,
      );
      final json = partial.lastPatch!.toJson();
      expect(
        json.containsKey('isRead'),
        isFalse,
        reason: 'a stale client cannot un-read a chapter',
      );
      expect(json['lastPageRead'], 38);

      final offlineDb = testOfflineDatabase();
      addTearDown(offlineDb.close);
      await offlineDb.upsertChapterMetadata(
        id: 11,
        mangaId: 1,
        name: 'c11',
        chapterIndex: 11,
        isRead: true,
        lastPageRead: 0,
        isBookmarked: false,
        serverIsDownloaded: true,
        pageCount: 40,
        updatedAt: DateTime(2026),
      );
      await recordReadingProgressWithDependencies(
        offlineEnabled: true,
        offlineDatabase: offlineDb,
        repository: _PartialReadRepo(),
        chapterId: 11,
        lastPageRead: 38,
        isRead: false,
      );
      final row = (await offlineDb.chapterById(11))!;
      expect(row.isRead, isTrue, reason: 'only position updates');
      expect(row.lastPageRead, 38);
    },
  );
}
