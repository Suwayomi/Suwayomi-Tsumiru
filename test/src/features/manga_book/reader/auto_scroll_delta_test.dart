// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/infinity_continuous/multichapter_continuous_reader_mode.dart';

void main() {
  group('autoScrollDelta', () {
    test('advances one viewport over the interval', () {
      final d = autoScrollDelta(viewport: 1000, intervalSeconds: 5, dtMs: 5000);
      expect(d, closeTo(1000, 0.001));
    });

    test('scales linearly with elapsed frame time', () {
      final full = autoScrollDelta(
        viewport: 1000,
        intervalSeconds: 5,
        dtMs: 5000,
      );
      final quarter = autoScrollDelta(
        viewport: 1000,
        intervalSeconds: 5,
        dtMs: 1250,
      );
      expect(quarter, closeTo(full / 4, 0.001));
    });

    test('a shorter interval means a bigger per-frame delta', () {
      final slow = autoScrollDelta(
        viewport: 1000,
        intervalSeconds: 10,
        dtMs: 16,
      );
      final fast = autoScrollDelta(
        viewport: 1000,
        intervalSeconds: 5,
        dtMs: 16,
      );
      expect(fast, greaterThan(slow));
    });

    test('zero or negative interval means no motion', () {
      expect(autoScrollDelta(viewport: 1000, intervalSeconds: 0, dtMs: 16), 0);
      expect(autoScrollDelta(viewport: 1000, intervalSeconds: -1, dtMs: 16), 0);
    });

    test('zero elapsed time means no motion', () {
      expect(autoScrollDelta(viewport: 1000, intervalSeconds: 5, dtMs: 0), 0);
    });
  });

  group('autoScrollResumeAt', () {
    test('resumes at the next interval boundary', () {
      expect(
        autoScrollResumeAt(const Duration(milliseconds: 1500), 5),
        const Duration(seconds: 5),
      );
      expect(
        autoScrollResumeAt(const Duration(milliseconds: 12000), 5),
        const Duration(seconds: 15),
      );
    });

    test('a drag landing on a boundary waits the next full interval', () {
      expect(
        autoScrollResumeAt(const Duration(seconds: 10), 5),
        const Duration(seconds: 15),
      );
    });

    test('a later drag never resumes earlier than an earlier one', () {
      final early = autoScrollResumeAt(const Duration(milliseconds: 200), 5);
      final late = autoScrollResumeAt(const Duration(milliseconds: 4800), 5);
      expect(late, greaterThanOrEqualTo(early));
    });

    test('the pause never outlasts one interval', () {
      for (var ms = 0; ms < 5000; ms += 250) {
        final elapsed = Duration(milliseconds: ms);
        final wait = autoScrollResumeAt(elapsed, 5) - elapsed;
        expect(wait, lessThanOrEqualTo(const Duration(seconds: 5)));
        expect(wait, greaterThan(Duration.zero));
      }
    });

    test('zero or negative interval resumes immediately', () {
      expect(
        autoScrollResumeAt(const Duration(seconds: 3), 0),
        const Duration(seconds: 3),
      );
      expect(
        autoScrollResumeAt(const Duration(seconds: 3), -1),
        const Duration(seconds: 3),
      );
    });
  });
}
