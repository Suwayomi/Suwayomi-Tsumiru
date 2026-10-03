// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/update_status/update_status_model.dart';

Fragment$UpdateProgressDto _progress(bool running, int total, int finished) =>
    Fragment$UpdateProgressDto(
      isRunning: running,
      totalJobs: total,
      finishedJobs: finished,
    );

void main() {
  test('the running signal follows the one progress feed and changes only on '
      'its edges, not on every progress push', () async {
    final feed = StreamController<UpdateProgressDto?>();
    addTearDown(feed.close);
    final container = ProviderContainer(
      overrides: [
        updateProgressSocketProvider.overrideWith((ref) => feed.stream),
      ],
    );
    addTearDown(container.dispose);
    final seen = <bool?>[];
    container.listen(
      updateRunningSocketProvider,
      (_, next) => seen.add(next.value),
    );

    for (final p in [
      _progress(false, 0, 0),
      _progress(true, 360, 0),
      _progress(true, 360, 12),
      _progress(true, 360, 200),
      _progress(true, 360, 359),
      _progress(false, 360, 360),
      _progress(false, 360, 360),
    ]) {
      feed.add(p);
      await pumpEventQueue();
    }

    expect(seen, [false, true, false]);
  });

  test('progress counts read straight off the server totals', () {
    final p = _progress(true, 100, 37);
    expect(p.total, 100);
    expect(p.updateChecked, 37);
    expect(p.isUpdateChecking, isTrue);
    expect(_progress(false, 100, 100).isUpdateChecking, isFalse);
    expect(_progress(false, 0, 0).isUpdateChecking, isFalse);
  });
}
