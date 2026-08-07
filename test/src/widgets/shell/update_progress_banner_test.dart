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
import 'package:tsumiru/src/features/browse_center/domain/manga_page/graphql/__generated__/fragment.graphql.dart'
    show Fragment$MangaPageDto;
import 'package:tsumiru/src/features/library/domain/category/graphql/__generated__/fragment.graphql.dart'
    show Fragment$CategoryPageDto;
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/fragments.graphql.dart'
    show Fragment$PageInfoDto;
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/shell/update_banner_state.dart';
import 'package:tsumiru/src/widgets/shell/update_progress_banner.dart';

Fragment$PageInfoDto _emptyPage() =>
    Fragment$PageInfoDto(hasNextPage: false, hasPreviousPage: false);

Fragment$UpdateStatusJobDto _jobs(int count) => Fragment$UpdateStatusJobDto(
      mangas: Fragment$MangaPageDto(
        nodes: const [],
        pageInfo: _emptyPage(),
        totalCount: count,
      ),
    );

Fragment$UpdateStatusDto$skippedCategories _emptyCategoryPage() =>
    Fragment$UpdateStatusDto$skippedCategories(
      categories: Fragment$CategoryPageDto(
        nodes: const [],
        pageInfo: _emptyPage(),
        totalCount: 0,
      ),
    );

Fragment$UpdateStatusDto _status({
  required bool isRunning,
  int pending = 0,
  int running = 0,
  int complete = 0,
  int failed = 0,
}) =>
    Fragment$UpdateStatusDto(
      isRunning: isRunning,
      pendingJobs: _jobs(pending),
      runningJobs: _jobs(running),
      completeJobs: _jobs(complete),
      failedJobs: _jobs(failed),
      skippedJobs: _jobs(0),
      skippedCategories: _emptyCategoryPage(),
      updatingCategories: Fragment$UpdateStatusDto$updatingCategories(
        categories: Fragment$CategoryPageDto(
          nodes: const [],
          pageInfo: _emptyPage(),
          totalCount: 0,
        ),
      ),
    );

/// A stream that never emits and never closes — models the heavy status feed
/// stalling mid-update (the server can't resolve the job-list fields), so the
/// StreamProvider stays in loading and `valueOrNull` is null throughout.
Stream<T> _stalled<T>() => Stream<T>.fromFuture(Completer<T>().future);

Future<void> _pump(
  WidgetTester tester, {
  // Visibility source (cheap running-only signal).
  Stream<bool?>? running,
  Future<bool?>? runningFallback,
  // Label source (heavy status feed; percent enrichment).
  Stream<Fragment$UpdateStatusDto?>? heavy,
  Future<Fragment$UpdateStatusDto?>? heavyFallback,
  bool prefOn = true,
}) async {
  SharedPreferences.setMockInitialValues(
    {'showUpdateProgressBanner': prefOn},
  );
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        updateRunningSocketProvider
            .overrideWith((ref) => running ?? Stream.value(false)),
        updateRunningSummaryProvider
            .overrideWith((ref) => runningFallback ?? Future.value(null)),
        updatesSocketProvider
            .overrideWith((ref) => heavy ?? _stalled()),
        updateSummaryProvider
            .overrideWith((ref) => heavyFallback ?? Future.value(null)),
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
    await _pump(tester, running: Stream.value(false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.byType(UpdateProgressBanner), findsOneWidget);
    expect(find.textContaining('Updating library'), findsNothing);
  });

  testWidgets('appears after the 1000ms debounce once running', (tester) async {
    await _pump(tester, running: Stream.value(true));
    await tester.pump();

    // Before the debounce fires, the banner must not have appeared yet.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Updating library'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Updating library…'), findsOneWidget);
  });

  testWidgets('optimistic arm shows the banner immediately, before the debounce',
      (tester) async {
    // Server still reports idle — but the user just triggered an update. The
    // banner must appear at once (bypassing the appear-debounce), so a pull
    // doesn't feel dead for the ~1.5s before the server confirms it's running.
    await _pump(tester, running: Stream.value(false));
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
  });

  testWidgets(
      'shows the running bar with indeterminate text when the heavy feed '
      'stalls (the bug this fix addresses)', (tester) async {
    // Running signal says "yes", but the heavy status feed never delivers —
    // exactly the large-update case where the server stalls on job lists.
    // The bar must still appear, showing "Updating library…", not nothing.
    await _pump(
      tester,
      running: Stream.value(true),
      heavy: _stalled(),
      heavyFallback: Completer<Fragment$UpdateStatusDto?>().future,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('Updating library…'), findsOneWidget);
  });

  testWidgets('enriches to floor-rounded percent when the heavy feed resolves',
      (tester) async {
    await _pump(
      tester,
      running: Stream.value(true),
      heavy: Stream.value(_status(isRunning: true, complete: 37, pending: 63)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    // The heavy feed is only subscribed once the bar is visible, so it first
    // shows "Updating library…" then enriches to the percent a frame later.
    await tester.pump();

    expect(find.text('Updating library (37% · 37/100)'), findsOneWidget);
  });

  testWidgets('hidden when the preference is off', (tester) async {
    await _pump(
      tester,
      running: Stream.value(true),
      heavy: Stream.value(_status(isRunning: true, complete: 1, pending: 1)),
      prefOn: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.textContaining('Updating library'), findsNothing);
  });

  testWidgets(
      'visibility falls back to the one-shot running query when the running '
      'socket errors', (tester) async {
    await _pump(
      tester,
      running: Stream<bool?>.error(Exception('ws down')),
      runningFallback: Future.value(true),
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
