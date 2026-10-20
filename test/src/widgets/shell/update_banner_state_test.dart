// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/widgets/shell/update_banner_state.dart';

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      // arm() reads this to seed whether a run is already in flight.
      updateProgressSocketProvider.overrideWith(
        (ref) => Stream.value(
          Fragment$UpdateProgressDto(
            isRunning: false,
            totalJobs: 0,
            finishedJobs: 0,
          ),
        ),
      ),
    ],
  );
  // Riverpod 3 pauses/disposes unlistened providers, so a one-shot .future
  // read leaves the socket provider mid-loading at teardown ("disposed during
  // loading state"). A persistent listener keeps it alive and settled.
  container.listen(updateRunningSocketProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('UpdateOptimistic', () {
    test('holds through pre-start idle and releases on the end edge', () async {
      final c = _container();
      // Resolve the seed read to "not running" before arming.
      await c.read(updateProgressSocketProvider.future);
      final notifier = c.read(updateOptimisticProvider.notifier);

      // OnRealRunning before arm is a no-op.
      notifier.onRealRunning(false);
      expect(c.read(updateOptimisticProvider), isFalse);
      notifier.onRealRunning(true);
      expect(c.read(updateOptimisticProvider), isFalse);

      notifier.arm();
      // Pre-start idle frames must not clear the optimistic hold.
      notifier.onRealRunning(false);
      expect(c.read(updateOptimisticProvider), isTrue);

      // Server confirms running, then finishes.
      notifier.onRealRunning(true);
      expect(
        c.read(updateOptimisticProvider),
        isTrue,
        reason: 'still held while the real run is in progress',
      );
      notifier.onRealRunning(false);
      expect(
        c.read(updateOptimisticProvider),
        isFalse,
        reason: 'released on the running→idle edge',
      );
    });
  });
}
