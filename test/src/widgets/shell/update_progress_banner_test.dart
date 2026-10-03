// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/shell/update_banner_state.dart';
import 'package:tsumiru/src/widgets/shell/update_progress_banner.dart';

Fragment$UpdateProgressDto _progress({
  required bool isRunning,
  int total = 0,
  int finished = 0,
}) => Fragment$UpdateProgressDto(
  isRunning: isRunning,
  totalJobs: total,
  finishedJobs: finished,
);

Future<void> _pump(
  WidgetTester tester, {
  // The one progress feed: on/off and the counts.
  Stream<Fragment$UpdateProgressDto?>? progress,
  Future<Fragment$UpdateProgressDto?>? progressFallback,
  bool prefOn = true,
}) async {
  SharedPreferences.setMockInitialValues({'showUpdateProgressBanner': prefOn});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        updateProgressSocketProvider.overrideWith(
          (ref) => progress ?? Stream.value(_progress(isRunning: false)),
        ),
        updateProgressSummaryProvider.overrideWith(
          (ref) => progressFallback ?? Future.value(null),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: UpdateProgressBanner()),
      ),
    ),
  );
}

void main() {
  testWidgets('hidden while idle', (tester) async {
    await _pump(tester, progress: Stream.value(_progress(isRunning: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.byType(UpdateProgressBanner), findsOneWidget);
    expect(find.textContaining('Updating library'), findsNothing);
  });

  testWidgets('appears after the 1000ms debounce once running', (tester) async {
    await _pump(tester, progress: Stream.value(_progress(isRunning: true)));
    await tester.pump();

    // Before the debounce fires, the banner must not have appeared yet.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Updating library'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Updating library…'), findsOneWidget);
  });

  testWidgets(
    'optimistic arm shows the banner immediately, before the debounce',
    (tester) async {
      // Server still reports idle — but the user just triggered an update. The
      // banner must appear at once (bypassing the appear-debounce), so a pull
      // doesn't feel dead for the ~1.5s before the server confirms it's running.
      await _pump(tester, progress: Stream.value(_progress(isRunning: false)));
      await tester.pump();
      expect(find.textContaining('Updating library'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(UpdateProgressBanner)),
      );
      container.read(updateOptimisticProvider.notifier).arm();
      await tester.pump(); // no debounce wait

      expect(find.text('Updating library…'), findsOneWidget);

      // Drain the arm's safety timeout so no timer outlives the test.
      await tester.pump(const Duration(seconds: 13));
    },
  );

  testWidgets(
    'shows the running bar with indeterminate text until counts arrive',
    (tester) async {
      // Running, but no job counted yet (the run is still being set up): the
      // bar must show "Updating library…", not a 0% or nothing.
      await _pump(
        tester,
        progress: Stream.value(_progress(isRunning: true)),
        progressFallback: Completer<Fragment$UpdateProgressDto?>().future,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.text('Updating library…'), findsOneWidget);
    },
  );

  testWidgets('shows the floor-rounded percent from the progress counts', (
    tester,
  ) async {
    await _pump(
      tester,
      progress: Stream.value(
        _progress(isRunning: true, total: 100, finished: 37),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();

    expect(find.text('Updating library (37% · 37/100)'), findsOneWidget);
  });

  testWidgets('hidden when the preference is off', (tester) async {
    await _pump(
      tester,
      progress: Stream.value(_progress(isRunning: true, total: 2, finished: 1)),
      prefOn: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.textContaining('Updating library'), findsNothing);
  });

  testWidgets('visibility falls back to the one-shot progress query when the '
      'progress socket errors', (tester) async {
    await _pump(
      tester,
      progress: Stream<Fragment$UpdateProgressDto?>.error(Exception('ws down')),
      progressFallback: Future.value(_progress(isRunning: true)),
    );
    await tester.pump();
    // The error->invalidate round trip only lands on the frame the first
    // (stale "not running") debounce timer fires, which then starts a
    // second full 1000ms debounce for the freshly-discovered "running"
    // state — so settling takes ~2000ms here, not one debounce window.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1100));

    expect(find.text('Updating library…'), findsOneWidget);
  });
}
