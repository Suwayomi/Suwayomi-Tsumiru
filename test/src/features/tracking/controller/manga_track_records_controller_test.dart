// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/tracking/controller/manga_track_records_controller.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';

void main() {
  // A minimal fake client — the stub repo never actually calls it.
  final fakeClient = GraphQLClient(
    link: HttpLink('http://localhost'),
    cache: GraphQLCache(),
  );

  group('mangaTrackRecordsProvider', () {
    test('defaults to empty list when repository returns null', () async {
      final container = ProviderContainer(
        overrides: [
          trackerRepositoryProvider.overrideWith(
            (ref) => _StubTrackerRepository(fakeClient, records: null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        mangaTrackRecordsProvider(mangaId: 42).future,
      );

      expect(result, isEmpty);
    });

    test('returns list from repository when records exist', () async {
      final fakeRecord = Fragment$TrackRecordDto(
        id: 1,
        trackerId: 1,
        remoteId: 'remote-1',
        title: 'Test Manga',
        remoteUrl: 'https://example.com',
        status: 1,
        lastChapterRead: 0.0,
        totalChapters: 10,
        score: 0.0,
        displayScore: '0',
        startDate: '',
        finishDate: '',
        private: false,
      );

      final container = ProviderContainer(
        overrides: [
          trackerRepositoryProvider.overrideWith(
            (ref) => _StubTrackerRepository(fakeClient, records: [fakeRecord]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        mangaTrackRecordsProvider(mangaId: 42).future,
      );

      expect(result, hasLength(1));
      expect(result.first.id, 1);
      expect(result.first.title, 'Test Manga');
    });
  });
}

/// Stub that short-circuits getMangaTrackRecords; the GraphQLClient is never
/// invoked so any valid client object is sufficient for construction.
class _StubTrackerRepository extends TrackerRepository {
  _StubTrackerRepository(super.client, {required this.records});

  final List<Fragment$TrackRecordDto>? records;

  @override
  Future<List<Fragment$TrackRecordDto>?> getMangaTrackRecords(
    int mangaId,
  ) async =>
      records;
}
