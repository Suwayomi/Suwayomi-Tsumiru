// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/tracking/domain/track_progress_gate.dart';

void main() {
  group('shouldTrackProgress', () {
    test('auto path gates on enabledAfterReading, not manual mark-read', () {
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
      // The manual flag does not gate the auto path.
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

    test('manual path gates on enabledManualMarkRead, not after-reading', () {
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
      // The after-reading flag does not gate the manual path.
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

    test('read and record gates apply to both paths', () {
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
      expect(
        shouldTrackProgress(
          isRead: false,
          enabledAfterReading: true,
          enabledManualMarkRead: true,
          manual: true,
          trackRecordCount: 1,
        ),
        isFalse,
      );
      expect(
        shouldTrackProgress(
          isRead: true,
          enabledAfterReading: true,
          enabledManualMarkRead: true,
          manual: true,
          trackRecordCount: 0,
        ),
        isFalse,
      );
    });
  });
}
