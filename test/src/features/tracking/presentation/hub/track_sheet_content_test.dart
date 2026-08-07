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
  testWidgets(
    'TrackSheetContent shows "Add tracking" for a logged-in tracker with no record',
    (tester) async {
      final tracker = _fakeTracker();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackersProvider.overrideWith((ref) async => [tracker]),
            mangaTrackRecordsProvider(
              mangaId: 1,
            ).overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: TrackSheetContent(mangaId: 1)),
          ),
        ),
      );

      // Let both futures resolve.
      await tester.pump();
      await tester.pump();

      expect(find.text('Add tracking'), findsOneWidget);
    },
  );

  testWidgets(
    'TrackSheetContent shows empty-state when no tracker is logged in',
    (tester) async {
      final tracker = _fakeTracker(isLoggedIn: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackersProvider.overrideWith((ref) async => [tracker]),
            mangaTrackRecordsProvider(
              mangaId: 1,
            ).overrideWith((ref) async => []),
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

      expect(find.text('Log in to a tracker'), findsOneWidget);
    },
  );

  testWidgets(
    'TrackSheetContent shows "Log in to edit" card for a logged-out tracker with a bound record',
    (tester) async {
      final tracker = _fakeTracker(isLoggedIn: false);
      final record = _fakeRecord();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackersProvider.overrideWith((ref) async => [tracker]),
            mangaTrackRecordsProvider(
              mangaId: 1,
            ).overrideWith((ref) async => [record]),
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

      // The bound title is shown read-only.
      expect(find.text('My Bound Manga'), findsOneWidget);
      // The login prompt button is present.
      expect(find.text('Log in to edit'), findsOneWidget);
      // The generic empty-state is NOT shown because there is a bound record.
      expect(find.text('Log in to a tracker'), findsNothing);
    },
  );

  testWidgets(
    'TrackSheetContent shows error state when trackersProvider errors',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackersProvider.overrideWith(
              (ref) async => throw Exception('network error'),
            ),
            mangaTrackRecordsProvider(
              mangaId: 1,
            ).overrideWith((ref) async => []),
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

      // The error message and retry button are rendered.
      expect(find.text('Exception: network error'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    },
  );
}
