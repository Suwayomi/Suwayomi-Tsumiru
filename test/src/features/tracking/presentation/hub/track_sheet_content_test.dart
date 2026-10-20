// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/tracking/controller/manga_track_records_controller.dart';
import 'package:tsumiru/src/features/tracking/data/graphql/__generated__/query.graphql.dart';
import 'package:tsumiru/src/features/tracking/data/tracker_repository.dart';
import 'package:tsumiru/src/features/tracking/presentation/hub/track_sheet.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Fragment$TrackerDto _fakeTracker({bool isLoggedIn = true, int id = 1}) =>
    Fragment$TrackerDto(
      id: id,
      name: 'MyAnimeList',
      icon: 'https://example.com/mal.png',
      isLoggedIn: isLoggedIn,
      isTokenExpired: false,
      supportsTrackDeletion: false,
      supportsPrivateTracking: false,
      supportsReadingDates: false,
      scores: const [],
      statuses: const [],
    );

Fragment$TrackRecordDto _fakeRecord({int trackerId = 1}) =>
    Fragment$TrackRecordDto(
      id: 1,
      trackerId: trackerId,
      remoteId: '42',
      title: 'My Bound Manga',
      remoteUrl: 'https://myanimelist.net/manga/42',
      status: 0,
      lastChapterRead: 0.0,
      totalChapters: 0,
      score: 0.0,
      displayScore: '',
      startDate: '',
      finishDate: '',
      private: false,
    );

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required Fragment$TrackerDto tracker,
    required List<Fragment$TrackRecordDto> records,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackersProvider.overrideWith((ref) async => [tracker]),
          mangaTrackRecordsProvider(
            mangaId: 1,
          ).overrideWith((ref) async => records),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TrackSheetContent(mangaId: 1)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('logged-in and logged-out cards', (tester) async {
    // A logged-in tracker with no record offers Add tracking.
    await pumpSheet(tester, tracker: _fakeTracker(), records: []);
    expect(find.text('Add tracking'), findsOneWidget);

    // A logged-out tracker with no record asks for a login.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSheet(
      tester,
      tracker: _fakeTracker(isLoggedIn: false),
      records: [],
    );
    expect(find.text('Log in to a tracker'), findsOneWidget);

    // A logged-out tracker with a bound record shows it read-only and offers
    // login to edit, not the generic empty state.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSheet(
      tester,
      tracker: _fakeTracker(isLoggedIn: false),
      records: [_fakeRecord()],
    );
    expect(find.text('My Bound Manga'), findsOneWidget);
    expect(find.text('Log in to edit'), findsOneWidget);
    expect(find.text('Log in to a tracker'), findsNothing);
  });
}
