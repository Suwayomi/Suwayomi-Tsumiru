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

      expect(File(path).lengthSync(), lessThanOrEqualTo(256 * 1024),
          reason: 'the log must stay bounded');
      final content = File(path).readAsStringSync();
      expect(content, contains('line 11999'),
          reason: 'the newest entry must survive the trim');
      expect(content, isNot(contains('line 0 with')),
          reason: 'the oldest entries must be dropped');
      // Trim starts on a line boundary — no half entry at the top.
      expect(content.startsWith('line '), isTrue);
    });

    test('an existing huge log (pre-cap) is trimmed on the next write', () {
      final dir = Directory.systemTemp.createTempSync('crashlog-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/crash.log';

      // Simulate a log that grew unbounded before the cap shipped: 1 MB of
      // old entries written directly, bypassing the cap.
      final old = StringBuffer();
      for (var i = 0; i < 20000; i++) {
        old.writeln('OLD entry $i padding padding padding');
      }
      File(path).writeAsStringSync(old.toString());
      expect(File(path).lengthSync(), greaterThan(256 * 1024));

      // A single new error write must bring it back under the cap.
      writeCrashLog(path, 'NEW entry after the cap shipped\n');

      expect(File(path).lengthSync(), lessThanOrEqualTo(256 * 1024));
      final content = File(path).readAsStringSync();
      expect(content, contains('NEW entry after the cap shipped'));
      expect(content, isNot(contains('OLD entry 0 ')));
    });

    test('clear deletes the log file', () {
      final dir = Directory.systemTemp.createTempSync('crashlog-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/crash.log';

      writeCrashLog(path, 'boom\n');
      expect(File(path).existsSync(), isTrue);
      clearCrashLog(path);
      expect(File(path).existsSync(), isFalse);
      // Reading a cleared log is null, not a crash.
      expect(readCrashLog(path), isNull);
    });

    test('a null path is a no-op everywhere', () {
      expect(() => writeCrashLog(null, 'x'), returnsNormally);
      expect(() => clearCrashLog(null), returnsNormally);
      expect(readCrashLog(null), isNull);
    });
  });
}
