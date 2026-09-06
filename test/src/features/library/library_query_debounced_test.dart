// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';

void main() {
  group('LibraryQueryDebounced', () {
    test('mirrors the raw query at build time', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(libraryQueryDebouncedProvider, (_, __) {});

      expect(container.read(libraryQueryDebouncedProvider), isNull);
    });

    test(
      'a burst of keystrokes only propagates the last value, after 300ms quiet',
      () {
        fakeAsync((async) {
          final container = ProviderContainer();
          container.listen(libraryQueryDebouncedProvider, (_, __) {});
          final notifier = container.read(libraryQueryProvider.notifier);

          notifier.update('o');
          async.elapse(const Duration(milliseconds: 100));
          notifier.update('on');
          async.elapse(const Duration(milliseconds: 100));
          notifier.update('one');

          // Each keystroke restarted the window, so 200ms after the last one
          // (100ms + 100ms of quiet accumulated below) is still under 300ms.
          async.elapse(const Duration(milliseconds: 200));
          expect(container.read(libraryQueryDebouncedProvider), isNull);

          // Past 300ms of quiet since 'one': now it propagates.
          async.elapse(const Duration(milliseconds: 101));
          expect(container.read(libraryQueryDebouncedProvider), 'one');

          container.dispose();
        });
      },
    );

    test('a later keystroke restarts the debounce window', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        container.listen(libraryQueryDebouncedProvider, (_, __) {});
        final notifier = container.read(libraryQueryProvider.notifier);

        notifier.update('re');
        async.elapse(const Duration(milliseconds: 299));
        expect(container.read(libraryQueryDebouncedProvider), isNull);

        // Just before the window elapses, another keystroke restarts it.
        notifier.update('rez');
        async.elapse(const Duration(milliseconds: 299));
        expect(container.read(libraryQueryDebouncedProvider), isNull);

        async.elapse(const Duration(milliseconds: 2));
        expect(container.read(libraryQueryDebouncedProvider), 'rez');

        container.dispose();
      });
    });

    test('clearing the query (null) still propagates after the delay', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        container.listen(libraryQueryDebouncedProvider, (_, __) {});
        final notifier = container.read(libraryQueryProvider.notifier);

        notifier.update('abc');
        async.elapse(const Duration(milliseconds: 300));
        expect(container.read(libraryQueryDebouncedProvider), 'abc');

        notifier.update(null);
        async.elapse(const Duration(milliseconds: 300));
        expect(container.read(libraryQueryDebouncedProvider), isNull);

        container.dispose();
      });
    });
  });
}
