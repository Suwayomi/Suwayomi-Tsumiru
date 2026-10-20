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
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
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
  bool reduceMotion = false,
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
        if (reduceMotion)
          appReduceMotionProvider.overrideWith(_ReduceMotionOn.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ReduceMotionScope(child: child!),
        home: const Scaffold(body: UpdateProgressBanner()),
      ),
    ),
  );
}

class _ReduceMotionOn extends AppReduceMotion {
  @override
  bool build() => true;
}

void main() {
  testWidgets('hidden while idle, appears after the 1000ms debounce', (
    tester,
  ) async {
    await _pump(tester, progress: Stream.value(_progress(isRunning: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byType(UpdateProgressBanner), findsOneWidget);
    expect(find.textContaining('Updating library'), findsNothing);

    // Running: not before the debounce, then the banner.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, progress: Stream.value(_progress(isRunning: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Updating library'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Updating library…'), findsOneWidget);
  });

  testWidgets('reduced motion shows the banner at once without resizing', (
    tester,
  ) async {
    await _pump(
      tester,
      progress: Stream.value(_progress(isRunning: true)),
      reduceMotion: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();

    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.text('Updating library…'), findsOneWidget);
  });

  testWidgets('shows the floor-rounded percent once counts arrive', (
    tester,
  ) async {
    // Running, but no job counted yet: indeterminate text, never 0%.
    await _pump(
      tester,
      progress: Stream.value(_progress(isRunning: true)),
      progressFallback: Completer<Fragment$UpdateProgressDto?>().future,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Updating library…'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('preference off hides it; optimistic arm and socket-error '
      'fallback still show it', (tester) async {
    await _pump(
      tester,
      progress: Stream.value(_progress(isRunning: true, total: 2, finished: 1)),
      prefOn: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.textContaining('Updating library'), findsNothing);

    // Optimistic arm: server still idle, but the banner appears at once.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, progress: Stream.value(_progress(isRunning: false)));
    await tester.pump();
    expect(find.textContaining('Updating library'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UpdateProgressBanner)),
    );
    container.read(updateOptimisticProvider.notifier).arm();
    await tester.pump();
    expect(find.text('Updating library…'), findsOneWidget);
    // Drain the arm's safety timeout so no timer outlives the test.
    await tester.pump(const Duration(seconds: 13));

    // Socket error: visibility falls back to the one-shot progress query.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      progress: Stream<Fragment$UpdateProgressDto?>.error(Exception('ws down')),
      progressFallback: Future.value(_progress(isRunning: true)),
    );
    await tester.pump();
    // The error->invalidate round trip lands on the first (stale "not
    // running") debounce frame, which starts a second 1000ms debounce.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Updating library…'), findsOneWidget);
  });
}
