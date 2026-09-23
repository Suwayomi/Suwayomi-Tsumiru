// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

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
}
