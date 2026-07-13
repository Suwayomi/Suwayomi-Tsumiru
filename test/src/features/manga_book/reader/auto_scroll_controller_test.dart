// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/auto_scroll_controller.dart';

void main() {
  group('AutoScrollActive', () {
    test('defaults to off', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(autoScrollActiveProvider), isFalse);
    });

    test('start() turns it on', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(autoScrollActiveProvider.notifier).start();
      expect(container.read(autoScrollActiveProvider), isTrue);
    });

    test('stop() turns it off again', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(autoScrollActiveProvider.notifier);
      notifier.start();
      notifier.stop();
      expect(container.read(autoScrollActiveProvider), isFalse);
    });

    test('toggle() flips the state each call', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(autoScrollActiveProvider.notifier);
      notifier.toggle();
      expect(container.read(autoScrollActiveProvider), isTrue);
      notifier.toggle();
      expect(container.read(autoScrollActiveProvider), isFalse);
    });
  });
}
