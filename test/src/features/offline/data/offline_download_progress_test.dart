// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Progress drives the download arc on every row of a chapter list. Pages arrive
// far faster than a screen can show them, so publishing each one made hundreds
// of rows re-evaluate themselves for changes nobody could see — measured at
// roughly four times the CPU with a chapter list open versus without.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_progress.dart';

void main() {
  late ProviderContainer container;
  late OfflineDownloadProgress progress;

  setUp(() {
    container = ProviderContainer();
    progress = container.read(offlineDownloadProgressProvider.notifier);
  });
  tearDown(() => container.dispose());

  /// How many times listeners were told something changed.
  int countNotifications(void Function() body) {
    var n = 0;
    final sub = container.listen(
      offlineDownloadProgressProvider,
      (_, _) => n++,
    );
    body();
    sub.close();
    return n;
  }

  test('a long chapter publishes ~100 updates, not one per page', () {
    progress.start(1, total: 1000, done: 0);
    final n = countNotifications(() {
      for (var page = 1; page <= 1000; page++) {
        progress.start(1, total: 1000, done: page);
      }
    });
    expect(
      n,
      lessThanOrEqualTo(101),
      reason: 'one per visible percent, not one per page',
    );
    expect(n, greaterThan(50), reason: 'the arc must still actually move');
  });

  test('the final page always publishes, however long the chapter', () {
    // Otherwise a chapter can finish showing 99% forever.
    progress.start(1, total: 1000, done: 999);
    final n = countNotifications(
      () => progress.start(1, total: 1000, done: 1000),
    );
    expect(n, 1);
    expect(container.read(offlineDownloadProgressProvider)[1]!.done, 1000);
  });
}
