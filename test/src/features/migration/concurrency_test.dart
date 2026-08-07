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

    test('a cancelled waiter throws and never later steals a permit', () async {
      final sem = Semaphore(1);
      await sem.acquire(); // hold the only permit

      final token = CancelToken();
      final blocked = sem.acquire(token);
      // The waiter is queued; cancel it.
      token.cancel();
      await expectLater(blocked, throwsA(isA<CancelledException>()));
      expect(sem.queueLength, 0);

      // Releasing should restore the permit, not hand it to the dead waiter.
      sem.release();
      expect(sem.availablePermits, 1);
    });

    test('withPermit releases on error', () async {
      final sem = Semaphore(1);
      await expectLater(
        sem.withPermit(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(sem.availablePermits, 1);
    });
  });

  group('RateLimiter', () {
    test('spaces successive acquisitions by at least minInterval', () async {
      final limiter =
          RateLimiter(minInterval: const Duration(milliseconds: 50));
      final sw = Stopwatch()..start();
      await limiter.acquire();
      await limiter.acquire();
      await limiter.acquire();
      sw.stop();
      // Two intervals between three grants → ≥ ~100ms.
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(90));
    });

    test('concurrent callers are still serialized and paced', () async {
      final limiter =
          RateLimiter(minInterval: const Duration(milliseconds: 30));
      final sw = Stopwatch()..start();
      await Future.wait([limiter.acquire(), limiter.acquire(), limiter.acquire()]);
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(55));
    });

    test('a cancelled wait throws without stalling the queue', () async {
      final limiter =
          RateLimiter(minInterval: const Duration(milliseconds: 200));
      await limiter.acquire(); // first grant is immediate
      final token = CancelToken();
      final blocked = limiter.acquire(token); // must wait ~200ms
      token.cancel();
      await expectLater(blocked, throwsA(isA<CancelledException>()));
      // The queue is not wedged — a fresh acquire still completes.
      await limiter.acquire();
    });
  });
}
