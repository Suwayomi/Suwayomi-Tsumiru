// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';
import 'package:tsumiru/src/utils/crash/provider_failure_logger.dart';

final _failing = FutureProvider<int>(
  (ref) async => throw StateError('boom'),
  name: 'failingProvider',
);

final _failingFamily = FutureProvider.family<int, int>(
  (ref, id) async => throw StateError('boom $id'),
  name: 'failingFamily',
);

final _offline = FutureProvider<int>(
  (ref) async => throw const SocketException('unreachable'),
  name: 'offlineProvider',
);

void main() {
  late List<String> lines;
  late ProviderContainer container;

  setUp(() {
    lines = [];
    setDiagnosticSink(lines.add);
    container = ProviderContainer(
      observers: [ProviderFailureLogger(now: () => DateTime(2026, 9, 23))],
      retry: (_, _) => null,
    );
  });
  tearDown(() {
    container.dispose();
    setDiagnosticSink(null);
  });

  Future<void> fail(FutureProvider<int> provider) async {
    final sub = container.listen(provider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    sub.close();
  }

  test('logs the provider name, the error and its stack trace', () async {
    await fail(_failing);
    expect(lines, hasLength(1));
    expect(lines.single, contains('provider-failed: failingProvider'));
    expect(lines.single, contains('StateError: Bad state: boom'));
    expect(lines.single, contains('provider_failure_logger_test.dart'));
  });

  test('includes the family argument', () async {
    await fail(_failingFamily(7));
    expect(lines.single, contains('provider-failed: failingFamily(7)'));
  });

  test('logs each provider/error pair once per session', () async {
    await fail(_failing);
    container.invalidate(_failing);
    await fail(_failing);
    expect(lines, hasLength(1));
  });

  test(
    'skips connection errors, expected while the server is unreachable',
    () async {
      await fail(_offline);
      expect(lines, isEmpty);
    },
  );
}
