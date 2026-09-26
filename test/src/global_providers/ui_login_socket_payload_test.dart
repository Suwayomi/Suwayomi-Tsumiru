// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';

void main() {
  test('refreshes a due token before reading it, so the socket is not '
      'bound to an expired one', () async {
    var token = 'expired';
    final calls = <String>[];
    final payload = await uiLoginSocketPayload(
      isCurrentSession: () => true,
      refreshIfDue: () async {
        calls.add('refresh');
        token = 'fresh';
      },
      readToken: () async {
        calls.add('read');
        return token;
      },
    );
    expect(calls, ['refresh', 'read']);
    expect(payload, {'Authorization': 'fresh'});
  });

  test('a failed refresh still sends the current token', () async {
    final payload = await uiLoginSocketPayload(
      isCurrentSession: () => true,
      refreshIfDue: () async => throw Exception('offline'),
      readToken: () async => 'current',
    );
    expect(payload, {'Authorization': 'current'});
  });

  test('no token sends an empty payload', () async {
    for (final token in [null, '']) {
      final payload = await uiLoginSocketPayload(
        isCurrentSession: () => true,
        refreshIfDue: () async {},
        readToken: () async => token,
      );
      expect(payload, isEmpty);
    }
  });

  test(
    'a session change before or during the read aborts the connect',
    () async {
      await expectLater(
        uiLoginSocketPayload(
          isCurrentSession: () => false,
          refreshIfDue: () async {},
          readToken: () async => 'token',
        ),
        throwsStateError,
      );
      var current = true;
      await expectLater(
        uiLoginSocketPayload(
          isCurrentSession: () => current,
          refreshIfDue: () async {},
          readToken: () async {
            current = false;
            return 'token';
          },
        ),
        throwsStateError,
      );
    },
  );

  group('ws-auth diagnostics', () {
    final lines = <String>[];
    setUp(() {
      lines.clear();
      setDiagnosticSink(lines.add);
    });
    tearDown(() => setDiagnosticSink(null));

    test('logs a failed refresh and the expiry the socket binds with',
        () async {
      final expired = _jwt(
        DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      await uiLoginSocketPayload(
        isCurrentSession: () => true,
        refreshIfDue: () async => throw StateError('not hydrated'),
        readToken: () async => expired,
      );
      expect(lines, hasLength(2));
      expect(
        lines[0],
        contains('ws-auth: connect-refresh threw cause=StateError'),
      );
      expect(lines[1], matches(RegExp(r'ws-auth: connect-init expIn=-\d+s')));
      expect(lines.join(), isNot(contains(expired)));
    });

    test('logs an aborted connect', () async {
      await expectLater(
        uiLoginSocketPayload(
          isCurrentSession: () => false,
          refreshIfDue: () async {},
          readToken: () async => null,
        ),
        throwsStateError,
      );
      expect(
        lines.single,
        contains('connect-init aborted=session-changed-before'),
      );
    });

    test('describes missing and undecodable tokens', () {
      expect(describeSocketToken(null), 'token=none');
      expect(describeSocketToken('opaque'), 'exp=unknown');
    });
  });

  test('only a present, unexpired token binds the socket to its user', () {
    final now = DateTime.now().toUtc();
    expect(socketTokenIsLive(null), isFalse);
    expect(socketTokenIsLive(''), isFalse);
    expect(
      socketTokenIsLive(_jwt(now.subtract(const Duration(seconds: 1)))),
      isFalse,
    );
    expect(socketTokenIsLive(_jwt(now.add(const Duration(minutes: 5)))), isTrue);
    // No readable expiry: nothing a reconnect could improve on.
    expect(socketTokenIsLive('opaque'), isTrue);
  });
}

String _jwt(DateTime exp) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  // Only the exp claim matters: nothing here verifies the signature.
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}
