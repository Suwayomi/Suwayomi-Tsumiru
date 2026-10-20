// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/migration/domain/concurrency.dart';

void main() {
  group('Semaphore', () {
    test('bounds concurrency to its permit count', () async {
      final sem = Semaphore(3);
      var active = 0;
      var peak = 0;
      final gates = <Completer<void>>[];

      Future<void> task() => sem.withPermit(() async {
        active++;
        peak = active > peak ? active : peak;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        active--;
      });

      final futures = List.generate(10, (_) => task());
      // Let scheduling settle, then confirm no more than 3 ran at once.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(peak, 3);
      expect(active, 3);
      // Drain by index — completing a gate lets a queued task acquire a permit
      // and append a new gate, so we can't iterate a live snapshot.
      for (var i = 0; i < 10; i++) {
        while (gates.length <= i) {
          await Future<void>.delayed(Duration.zero);
        }
        gates[i].complete();
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(futures);
      expect(active, 0);
      expect(peak, 3);
    });

  });
}
