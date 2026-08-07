// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/tracking/controller/manga_track_records_controller.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/presentation/hub/widgets/track_editor.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _fakeClient = GraphQLClient(
  link: HttpLink('http://localhost'),
  cache: GraphQLCache(),
);

Fragment$TrackerDto _fakeTracker({
  bool supportsReadingDates = false,
  bool supportsTrackDeletion = false,
  bool supportsPrivateTracking = false,
}) =>
    Fragment$TrackerDto(
      id: 1,
      name: 'MyAnimeList',
      icon: 'https://example.com/mal.png',
      isLoggedIn: true,
      isTokenExpired: false,
      supportsTrackDeletion: supportsTrackDeletion,
      supportsPrivateTracking: supportsPrivateTracking,
      supportsReadingDates: supportsReadingDates,
      scores: const ['0.0', '1.0', '5.0', '10.0'],
      statuses: [
        Fragment$TrackerDto$statuses(name: 'Reading', value: 1),
        Fragment$TrackerDto$statuses(name: 'Completed', value: 2),
        Fragment$TrackerDto$statuses(name: 'On Hold', value: 3),
      ],
    );

Fragment$TrackRecordDto _fakeRecord({
  int status = 1,
  double lastChapterRead = 5.0,
  int totalChapters = 100,
  bool private = false,
}) =>
    Fragment$TrackRecordDto(
      id: 10,
      trackerId: 1,
      remoteId: '42',
      title: 'Test Manga',
      remoteUrl: 'https://myanimelist.net/manga/42',
      status: status,
      lastChapterRead: lastChapterRead,
      totalChapters: totalChapters,
      score: 0.0,
      displayScore: '0.0',
      startDate: '0',
      finishDate: '0',
      private: private,
    );

/// Stub repository — all mutations are no-ops by default.
class _StubTrackerRepository extends TrackerRepository {
  _StubTrackerRepository(super.client);

  @override
  Future<void> update({
    required int recordId,
    int? status,
    String? scoreString,
    double? lastChapterRead,
    String? startDate,
    String? finishDate,
    bool? private,
  }) async {}

  @override
  Future<void> unbind({
    required int recordId,
    bool? deleteRemoteTrack,
  }) async {}
}

Widget _testApp({
  required Fragment$TrackerDto tracker,
  required Fragment$TrackRecordDto record,
  _StubTrackerRepository? repo,
}) {
  final stubRepo = repo ?? _StubTrackerRepository(_fakeClient);
  return ProviderScope(
    overrides: [
      trackerRepositoryProvider.overrideWith((ref) => stubRepo),
      toastProvider.overrideWithValue(null),
      mangaTrackRecordsProvider(mangaId: 1)
          .overrideWith((ref) async => [record]),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TrackEditor(
          tracker: tracker,
          trackRecord: record,
          mangaId: 1,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests (RED — written before implementation)
// ---------------------------------------------------------------------------

void main() {
  testWidgets(
    'TrackEditor shows Status row and NO date rows when supportsReadingDates is false',
    (tester) async {
      final tracker = _fakeTracker(supportsReadingDates: false);
      final record = _fakeRecord(status: 1, lastChapterRead: 5.0);

      await tester.pumpWidget(_testApp(tracker: tracker, record: record));
      await tester.pump();
      await tester.pump();

      // Status row must be visible.
      expect(find.text('Status'), findsOneWidget);

      // Date rows must NOT appear when supportsReadingDates is false.
      expect(find.text('Start date'), findsNothing);
      expect(find.text('Finish date'), findsNothing);
    },
  );

  testWidgets(
    'TrackEditor shows Start date and Finish date rows when supportsReadingDates is true',
    (tester) async {
      final tracker = _fakeTracker(supportsReadingDates: true);
      final record = _fakeRecord(status: 1, lastChapterRead: 5.0);

      await tester.pumpWidget(_testApp(tracker: tracker, record: record));
      await tester.pump();
      await tester.pump();

      // Date rows MUST appear when supportsReadingDates is true.
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('Finish date'), findsOneWidget);
    },
  );

  testWidgets(
    'Chapters row shows "read / total" when the tracker reports a total',
    (tester) async {
      final tracker = _fakeTracker();
      final record = _fakeRecord(lastChapterRead: 5.0, totalChapters: 100);

      await tester.pumpWidget(_testApp(tracker: tracker, record: record));
      await tester.pump();
      await tester.pump();

      expect(find.text('5 / 100'), findsOneWidget);
    },
  );

  testWidgets(
    'Chapters row shows just the read count when no total is reported (no "/0")',
    (tester) async {
      final tracker = _fakeTracker();
      final record = _fakeRecord(lastChapterRead: 5.0, totalChapters: 0);

      await tester.pumpWidget(_testApp(tracker: tracker, record: record));
      await tester.pump();
      await tester.pump();

      expect(find.text('5'), findsOneWidget);
      expect(find.textContaining('/'), findsNothing);
    },
  );

  testWidgets(
    'Tapping the chapters value opens a number dialog to edit it',
    (tester) async {
      final tracker = _fakeTracker();
      final record = _fakeRecord(lastChapterRead: 5.0, totalChapters: 100);

      await tester.pumpWidget(_testApp(tracker: tracker, record: record));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('5 / 100'));
      await tester.pumpAndSettle();

      // A dialog with an editable field and Save/Cancel actions appears.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );
}
