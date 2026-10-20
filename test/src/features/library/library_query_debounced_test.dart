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
    test('a later keystroke restarts the debounce window', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        container.listen(libraryQueryDebouncedProvider, (_, _) {});
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
        container.listen(libraryQueryDebouncedProvider, (_, _) {});
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
