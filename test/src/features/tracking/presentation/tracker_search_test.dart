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
import 'package:tsumiru/src/features/tracking/controller/tracker_search_controller.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/presentation/hub/widgets/tracker_search.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _fakeClient = GraphQLClient(
  link: HttpLink('http://localhost'),
  cache: GraphQLCache(),
);

Fragment$TrackerDto _fakeTracker({bool supportsPrivate = false}) =>
    Fragment$TrackerDto(
      id: 1,
      name: 'MyAnimeList',
      icon: 'https://example.com/mal.png',
      isLoggedIn: true,
      isTokenExpired: false,
      supportsTrackDeletion: false,
      supportsPrivateTracking: supportsPrivate,
      supportsReadingDates: false,
      scores: const [],
      statuses: const [],
    );

Fragment$TrackSearchDto _fakeResult(
        {required String remoteId, required String title}) =>
    Fragment$TrackSearchDto(
      remoteId: remoteId,
      title: title,
      coverUrl: 'https://example.com/cover.jpg',
      publishingType: 'Manga',
      publishingStatus: 'Publishing',
      summary: 'A test manga summary.',
      trackingUrl: 'https://myanimelist.net/manga/$remoteId',
    );

/// Stub repository whose [bind] either completes normally or throws.
class _StubTrackerRepository extends TrackerRepository {
  _StubTrackerRepository(super.client, {this.bindShouldThrow = false});

  final bool bindShouldThrow;

  @override
  Future<Fragment$TrackRecordDto> bind({
    required int mangaId,
    required int trackerId,
    required String remoteId,
    required bool private,
  }) async {
    if (bindShouldThrow) throw Exception('network error');
    return Fragment$TrackRecordDto(
      id: 1,
      trackerId: trackerId,
      remoteId: remoteId,
      title: 'Test',
      remoteUrl: 'https://example.com',
      status: 1,
      lastChapterRead: 0.0,
      totalChapters: 0,
      score: 0.0,
      displayScore: '0',
      startDate: '',
      finishDate: '',
      private: private,
    );
  }
}

// Pump a widget with no toast (null) so Toast? null-safety keeps things safe.
Widget _testApp({
  required Fragment$TrackerDto tracker,
  required List<Fragment$TrackSearchDto> results,
  required _StubTrackerRepository repo,
  required VoidCallback onBound,
}) =>
    ProviderScope(
      overrides: [
        searchTrackerProvider(trackerId: tracker.id, query: 'test manga')
            .overrideWith((ref) async => results),
        trackerRepositoryProvider.overrideWith((ref) => repo),
        // Supply null toast — Toast? is always nullable in the provider contract.
        toastProvider.overrideWithValue(null),
        mangaTrackRecordsProvider(mangaId: 42)
            .overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TrackerSearch(
            mangaId: 42,
            mangaTitle: 'test manga',
            tracker: tracker,
            onBound: onBound,
          ),
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets(
    'TrackerSearch renders two result tiles when searchTrackerProvider returns two results',
    (tester) async {
      final tracker = _fakeTracker();
      final results = [
        _fakeResult(remoteId: '1', title: 'Result One'),
        _fakeResult(remoteId: '2', title: 'Result Two'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchTrackerProvider(trackerId: 1, query: 'test manga')
                .overrideWith((ref) async => results),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TrackerSearch(
                mangaId: 42,
                mangaTitle: 'test manga',
                tracker: tracker,
                onBound: () {},
              ),
            ),
          ),
        ),
      );

      // Let the initial build + future resolve.
      await tester.pump();
      await tester.pump();

      expect(find.text('Result One'), findsOneWidget);
      expect(find.text('Result Two'), findsOneWidget);
    },
  );

  testWidgets(
    'bind — success: calls onBound',
    (tester) async {
      final tracker = _fakeTracker();
      final results = [_fakeResult(remoteId: '42', title: 'Success Manga')];
      final stubRepo = _StubTrackerRepository(_fakeClient);
      bool onBoundCalled = false;

      await tester.pumpWidget(_testApp(
        tracker: tracker,
        results: results,
        repo: stubRepo,
        onBound: () => onBoundCalled = true,
      ));

      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Success Manga'));
      await tester.pump();

      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();

      expect(onBoundCalled, isTrue,
          reason: 'onBound must fire when bind succeeds');
    },
  );

  testWidgets(
    'bind — failure: does NOT call onBound',
    (tester) async {
      final tracker = _fakeTracker();
      final results = [_fakeResult(remoteId: '99', title: 'Error Manga')];
      final stubRepo =
          _StubTrackerRepository(_fakeClient, bindShouldThrow: true);
      bool onBoundCalled = false;

      await tester.pumpWidget(_testApp(
        tracker: tracker,
        results: results,
        repo: stubRepo,
        onBound: () => onBoundCalled = true,
      ));

      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Error Manga'));
      await tester.pump();

      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();

      expect(onBoundCalled, isFalse,
          reason: 'onBound must NOT fire when the mutation fails');
    },
  );
}
