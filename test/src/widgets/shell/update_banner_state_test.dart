// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/widgets/shell/update_banner_state.dart';

ProviderContainer _container({bool runningNow = false}) {
  final container = ProviderContainer(
    overrides: [
      // arm() reads this to seed whether a run is already in flight.
      updateRunningSocketProvider
          .overrideWith((ref) => Stream.value(runningNow)),
    ],
  );
  // Riverpod 3 pauses/disposes unlistened providers, so a one-shot .future
  // read leaves the socket provider mid-loading at teardown ("disposed during
  // loading state"). A persistent listener keeps it alive and settled.
  container.listen(updateRunningSocketProvider, (_, __) {});
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('UpdateOptimistic', () {
    test('defaults to off', () {
      final c = _container();
      expect(c.read(updateOptimisticProvider), isFalse);
    });

    test('arm() shows the banner immediately', () {
      final c = _container();
      c.read(updateOptimisticProvider.notifier).arm();
      expect(c.read(updateOptimisticProvider), isTrue);
    });

    test('hands back once a real run is seen to start then end', () async {
      final c = _container();
      // Resolve the seed read to "not running" before arming.
      await c.read(updateRunningSocketProvider.future);
      final notifier = c.read(updateOptimisticProvider.notifier);
      notifier.arm();

      // Server confirms running, then finishes.
      notifier.onRealRunning(true);
      expect(c.read(updateOptimisticProvider), isTrue,
          reason: 'still held while the real run is in progress');
      notifier.onRealRunning(false);
      expect(c.read(updateOptimisticProvider), isFalse,
          reason: 'released on the running→idle edge');
    });

    test('a second arm mid-run releases on the next idle edge, not 12s later',
        () async {
      final c = _container(runningNow: true);
      // Seed read resolves to "already running".
      await c.read(updateRunningSocketProvider.future);
      final notifier = c.read(updateOptimisticProvider.notifier);
      notifier.arm();
      expect(c.read(updateOptimisticProvider), isTrue);

      // The change-only stream never re-delivers `true`; the idle edge alone
      // must release the hold because arm() seeded "already seen running".
      notifier.onRealRunning(false);
      expect(c.read(updateOptimisticProvider), isFalse);
    });

    test('does not release on idle frames before the real run starts',
        () async {
      final c = _container();
      await c.read(updateRunningSocketProvider.future);
      final notifier = c.read(updateOptimisticProvider.notifier);
      notifier.arm();

      // Pre-start idle frames must NOT clear the optimistic hold.
      notifier.onRealRunning(false);
      expect(c.read(updateOptimisticProvider), isTrue);
    });

    test('onRealRunning before arm is a no-op', () {
      final c = _container();
      c.read(updateOptimisticProvider.notifier).onRealRunning(false);
      expect(c.read(updateOptimisticProvider), isFalse);
      c.read(updateOptimisticProvider.notifier).onRealRunning(true);
      expect(c.read(updateOptimisticProvider), isFalse);
    });

    test('safety timeout releases the hold after 12s if no run registers', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            updateRunningSocketProvider
                .overrideWith((ref) => const Stream.empty()),
          ],
        );
        addTearDown(container.dispose);

        container.read(updateOptimisticProvider.notifier).arm();
        expect(container.read(updateOptimisticProvider), isTrue);

        async.elapse(const Duration(seconds: 12));
        expect(container.read(updateOptimisticProvider), isFalse);
      });
    });
  });

  group('UpdateBannerVisible', () {
    test('defaults to false and set() flips it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(updateBannerVisibleProvider), isFalse);
      container.read(updateBannerVisibleProvider.notifier).set(true);
      expect(container.read(updateBannerVisibleProvider), isTrue);
    });
  });
}
