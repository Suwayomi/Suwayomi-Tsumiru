// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  test('refreshes a due token before reading it', () async {
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

    // A failed refresh still sends the current token.
    final failed = await uiLoginSocketPayload(
      isCurrentSession: () => true,
      refreshIfDue: () async => throw Exception('offline'),
      readToken: () async => 'current',
    );
    expect(failed, {'Authorization': 'current'});
  });

  test('an expired token is withheld; nothing to send stays empty', () async {
    final expired = _jwt(
      DateTime.now().toUtc().subtract(const Duration(minutes: 78)),
    );
    final payload = await uiLoginSocketPayload(
      isCurrentSession: () => true,
      refreshIfDue: () async => throw Exception('offline'),
      readToken: () async => expired,
    );
    expect(payload, isEmpty);

    for (final token in [null, '']) {
      final empty = await uiLoginSocketPayload(
        isCurrentSession: () => true,
        refreshIfDue: () async {},
        readToken: () async => token,
      );
      expect(empty, isEmpty);
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
}

String _jwt(DateTime exp) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  // Only the exp claim matters: nothing here verifies the signature.
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}
