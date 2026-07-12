// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/flush_progress_on_lifecycle.dart';

void main() {
  testWidgets('flushes pending progress when the app is backgrounded',
      (tester) async {
    var flushes = 0;
    await tester.pumpWidget(
      HookBuilder(
        builder: (context) {
          useFlushProgressOnAppLifecycle(() async => flushes++);
          return const SizedBox.shrink();
        },
      ),
    );

    // Drive resumed → … → paused, the sequence a mobile background produces;
    // AppLifecycleListener.onPause fires on the transition into paused.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(flushes, 1);
  });
}
