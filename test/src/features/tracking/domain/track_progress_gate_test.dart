// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/tracking/domain/track_progress_gate.dart';

void main() {
  group('shouldTrackProgress', () {
    // Baseline: all conditions met (auto path).
    test('returns true when all conditions are met (auto path)', () {
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: true,
          enabledManualMarkRead: true,
          manual: false,
          trackRecordCount: 1,
        ),
        isTrue,
      );
    });

    // isRead gate.
    test('returns false when isRead is false', () {
      expect(
        shouldTrackProgress(
          isRead: false,
          enabledAfterReading: true,
          enabledManualMarkRead: true,
          manual: false,
          trackRecordCount: 1,
        ),
        isFalse,
      );
    });

    // trackRecordCount gate.
    test('returns false when trackRecordCount is 0', () {
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: true,
          enabledManualMarkRead: true,
          manual: false,
          trackRecordCount: 0,
        ),
        isFalse,
      );
    });

    // Auto path gated on enabledAfterReading.
    test('returns false when auto path and enabledAfterReading is false', () {
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: false,
          enabledManualMarkRead: true,
          manual: false,
          trackRecordCount: 1,
        ),
        isFalse,
      );
    });

    // Auto path is not gated on enabledManualMarkRead.
    test('returns true for auto path even when enabledManualMarkRead is false',
        () {
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: true,
          enabledManualMarkRead: false,
          manual: false,
          trackRecordCount: 1,
        ),
        isTrue,
      );
    });

    // Manual path gated on enabledManualMarkRead.
    test('returns true when manual path and enabledManualMarkRead is true', () {
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: false,
          enabledManualMarkRead: true,
          manual: true,
          trackRecordCount: 1,
        ),
        isTrue,
      );
    });

    test('returns false when manual path and enabledManualMarkRead is false',
        () {
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: true,
          enabledManualMarkRead: false,
          manual: true,
          trackRecordCount: 1,
        ),
        isFalse,
      );
    });

    // Manual path is not gated on enabledAfterReading.
    test(
        'returns true for manual path even when enabledAfterReading is false',
        () {
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: false,
          enabledManualMarkRead: true,
          manual: true,
          trackRecordCount: 1,
        ),
        isTrue,
      );
    });
  });
}
