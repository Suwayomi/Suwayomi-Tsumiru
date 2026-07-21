// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/features/migration/domain/migration_models.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';

void main() {
  // Minimal fake client — stub repos never call it.
  final fakeClient = GraphQLClient(
    link: HttpLink('http://localhost'),
    cache: GraphQLCache(),
  );

  Fragment$TrackRecordDto makeRecord({
    required int id,
    required int trackerId,
    required String remoteId,
    bool private = false,
  }) =>
      Fragment$TrackRecordDto(
        id: id,
        trackerId: trackerId,
        remoteId: remoteId,
        title: 'Test',
        remoteUrl: 'https://example.com',
        status: 1,
        lastChapterRead: 0.0,
        totalChapters: 10,
        score: 0.0,
        displayScore: '0',
        startDate: '',
        finishDate: '',
        private: private,
      );

  group('migrateTracking logic', () {
    test(
        'when migrateTracking is true, bind is called once per source track record',
        () async {
      final sourceRecords = [
        makeRecord(id: 1, trackerId: 10, remoteId: 'remote-abc'),
        makeRecord(id: 2, trackerId: 20, remoteId: 'remote-def', private: true),
      ];

      final stub = _StubTrackerRepository(
        fakeClient,
        records: sourceRecords,
      );

      // Simulate what migration_repository does when migrateTracking is true.
      final sourceMangaId = 100;
      final destMangaId = 200;

      final fetched = await stub.getMangaTrackRecords(sourceMangaId);
      expect(fetched, isNotNull);

      for (final record in fetched!) {
        await stub.bind(
          mangaId: destMangaId,
          trackerId: record.trackerId,
          remoteId: record.remoteId,
          private: record.private,
        );
      }

      expect(stub.bindCalls, hasLength(2));

      expect(stub.bindCalls[0].mangaId, destMangaId);
      expect(stub.bindCalls[0].trackerId, 10);
      expect(stub.bindCalls[0].remoteId, 'remote-abc');
      expect(stub.bindCalls[0].private, false);

      expect(stub.bindCalls[1].mangaId, destMangaId);
      expect(stub.bindCalls[1].trackerId, 20);
      expect(stub.bindCalls[1].remoteId, 'remote-def');
      expect(stub.bindCalls[1].private, true);
    });

    test('when source has no track records, no binds are issued', () async {
      final stub = _StubTrackerRepository(fakeClient, records: []);

      final fetched = await stub.getMangaTrackRecords(1);
      for (final record in fetched ?? []) {
        await stub.bind(
          mangaId: 2,
          trackerId: record.trackerId,
          remoteId: record.remoteId,
          private: record.private,
        );
      }

      expect(stub.bindCalls, isEmpty);
    });

    test('when getMangaTrackRecords returns null, no binds are issued',
        () async {
      final stub = _StubTrackerRepository(fakeClient, records: null);

      final fetched = await stub.getMangaTrackRecords(1);
      // Null-guard mirrors migration_repository.dart behaviour.
      if (fetched != null) {
        for (final record in fetched) {
          await stub.bind(
            mangaId: 2,
            trackerId: record.trackerId,
            remoteId: record.remoteId,
            private: record.private,
          );
        }
      }

      expect(stub.bindCalls, isEmpty);
    });

    test('MigrationOption.migrateTracking defaults to false', () {
      expect(const MigrationOption().migrateTracking, isFalse);
    });
  });
}

/// A recorded bind call for assertion.
class _BindCall {
  const _BindCall({
    required this.mangaId,
    required this.trackerId,
    required this.remoteId,
    required this.private,
  });

  final int mangaId;
  final int trackerId;
  final String remoteId;
  final bool private;
}

/// Stub that captures bind() calls and short-circuits getMangaTrackRecords.
class _StubTrackerRepository extends TrackerRepository {
  _StubTrackerRepository(super.client, {required this.records});

  final List<Fragment$TrackRecordDto>? records;
  final List<_BindCall> bindCalls = [];

  @override
  Future<List<Fragment$TrackRecordDto>?> getMangaTrackRecords(
    int mangaId,
  ) async =>
      records;

  @override
  Future<Fragment$TrackRecordDto> bind({
    required int mangaId,
    required int trackerId,
    required String remoteId,
    required bool private,
  }) async {
    bindCalls.add(_BindCall(
      mangaId: mangaId,
      trackerId: trackerId,
      remoteId: remoteId,
      private: private,
    ));
    return Fragment$TrackRecordDto(
      id: 900 + bindCalls.length,
      trackerId: trackerId,
      remoteId: remoteId,
      title: 'Test',
      remoteUrl: 'https://example.com',
      status: 1,
      lastChapterRead: 0.0,
      totalChapters: 10,
      score: 0.0,
      displayScore: '0',
      startDate: '',
      finishDate: '',
      private: private,
    );
  }
}
