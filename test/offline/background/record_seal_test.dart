// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/offline/data/background/record_seal.dart';

Uint8List _key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + seed) % 256));

const _record = BackgroundTokenRecord(
  gen: 3,
  authType: 'uiLogin',
  endpoint: 'https://server.example',
  identityEpoch: 2,
  catalogServerId: 'catalog',
  originalRefreshToken: 'secret-original-refresh',
  notificationSessionId: 'session',
  accessToken: 'secret-access',
  refreshToken: 'secret-refresh',
  password: 'secret-password',
  basicCredential: 'Basic c2VjcmV0',
  simpleCookie: 'JSESSIONID=secret',
  extraHeaders: {'CF-Access-Client-Secret': 'secret-cf'},
);

void main() {
  setUp(() => RecordSeal.debugKey = _key(1));
  // Back to the suite-wide key from flutter_test_config.dart.
  tearDown(
    () => RecordSeal.debugKey = Uint8List.fromList(
      List<int>.generate(32, (i) => i),
    ),
  );

  test('secrets are sealed and a wrong key reads them as absent', () {
    final raw = jsonEncode(_record.toJson());
    expect(raw, isNot(contains('secret')));
    expect(raw, isNot(contains('c2VjcmV0')));
    // Identity metadata the workers match on without the key stays readable.
    expect(raw, contains('catalog'));

    // Another key: the record authenticates as nobody and matches no identity.
    RecordSeal.debugKey = _key(2);
    final read = BackgroundTokenRecord.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
    expect(read.accessToken, isNull);
    expect(read.refreshToken, isNull);
    expect(read.basicCredential, isNull);
    expect(read.extraHeaders, isEmpty);
    expect(read.catalogServerId, 'catalog');
    expect(read.sameIdentity(_record), isFalse);
  });
}
