// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/crash/crash_log_io.dart';

void main() {
  group('crash log', () {
    test('append caps the file and keeps the most recent entries', () {
      final dir = Directory.systemTemp.createTempSync('crashlog-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/crash.log';

      // Write well past the 256 KB cap (~5000 lines * ~45 bytes ≈ 225 KB…
      // bump the count so we definitely trigger a trim).
      for (var i = 0; i < 12000; i++) {
        writeCrashLog(path, 'line $i with some padding to add a few bytes\n');
      }

      expect(
        File(path).lengthSync(),
        lessThanOrEqualTo(256 * 1024),
        reason: 'the log must stay bounded',
      );
      final content = File(path).readAsStringSync();
      expect(
        content,
        contains('line 11999'),
        reason: 'the newest entry must survive the trim',
      );
      expect(
        content,
        isNot(contains('line 0 with')),
        reason: 'the oldest entries must be dropped',
      );
      // Trim starts on a line boundary — no half entry at the top.
      expect(content.startsWith('line '), isTrue);
    });
  });
}
