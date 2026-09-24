// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/crash/copy_crash_log.dart';

void main() {
  group('crashLogHeader', () {
    test('renders the exact four-line preamble', () {
      expect(
        crashLogHeader(
          appVersion: '1.3.2',
          buildNumber: '42',
          serverVersion: 'v2.1.1867',
          platform: 'android 15',
        ),
        'Tsumiru v1.3.2 (build 42)\n'
        'Server: v2.1.1867\n'
        'Platform: android 15\n'
        '---\n',
      );
    });

    test('keeps a literal unknown server version as unknown', () {
      final header = crashLogHeader(
        appVersion: '1.3.2',
        buildNumber: '42',
        serverVersion: 'unknown',
        platform: 'web',
      );
      expect(header, contains('\nServer: unknown\n'));
    });
  });

  group('crashLogForClipboard', () {
    test('returns null for a path with no log, header or not', () {
      final dir = Directory.systemTemp.createTempSync('crashlog-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/crash.log';

      expect(crashLogForClipboard(path), isNull);
      expect(
        crashLogForClipboard(
          path,
          header: crashLogHeader(
            appVersion: '1.3.2',
            buildNumber: '42',
            serverVersion: 'unknown',
            platform: 'web',
          ),
        ),
        isNull,
      );
      expect(crashLogForClipboard(null, header: 'anything'), isNull);
    });

    test('prepends the header and redacts the body', () {
      final dir = Directory.systemTemp.createTempSync('crashlog-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/crash.log';
      File(path).writeAsStringSync(
        '[2026-01-01] Exception: http://h/img?token=OLD.secret x\n',
      );

      const header =
          'Tsumiru v1.3.2 (build 42)\n'
          'Server: unknown\n'
          'Platform: web\n'
          '---\n';
      final out = crashLogForClipboard(path, header: header)!;

      expect(out.startsWith(header), isTrue);
      expect(out, contains('token=<redacted>'));
      expect(out.contains('OLD.secret'), isFalse);
      expect(
        out,
        '$header[2026-01-01] Exception: http://h/img?token=<redacted> x\n',
      );
    });

    test('with no header the result is exactly the redacted log', () {
      final dir = Directory.systemTemp.createTempSync('crashlog-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/crash.log';
      File(path).writeAsStringSync('plain failure, no tokens\n');

      expect(crashLogForClipboard(path), 'plain failure, no tokens\n');
    });
  });
}
