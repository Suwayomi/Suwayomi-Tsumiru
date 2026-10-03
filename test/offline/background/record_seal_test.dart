// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test('a persisted record carries none of its secrets in clear', () {
    final raw = jsonEncode(_record.toJson());
    expect(raw, isNot(contains('secret')));
    expect(raw, isNot(contains('c2VjcmV0')));
    // Identity metadata the workers match on without the key stays readable.
    expect(raw, contains('catalog'));
  });

  test('a sealed record reads back whole', () {
    final read = BackgroundTokenRecord.fromJson(
      jsonDecode(jsonEncode(_record.toJson())) as Map<String, Object?>,
    );
    expect(read.toJsonForTest(), _record.toJsonForTest());
    expect(read.sameIdentity(_record), isTrue);
  });

  test('a record from before sealing still reads, so an update loses no '
      'session', () {
    final legacy = <String, Object?>{..._record.toJsonForTest()};
    final read = BackgroundTokenRecord.fromJson(legacy);
    expect(read.toJsonForTest(), _record.toJsonForTest());
  });

  test('another key reads the secrets as absent: the record authenticates '
      'as nobody and matches no identity', () {
    final raw = jsonEncode(_record.toJson());
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

  test('a tampered record reads its secrets as absent', () {
    final json = _record.toJson();
    final sealed = json['sealed']! as String;
    final parts = sealed.split('.');
    final bytes = base64Decode(parts[2]);
    bytes[0] ^= 1;
    json['sealed'] = '${parts[0]}.${parts[1]}.${base64Encode(bytes)}';
    expect(BackgroundTokenRecord.fromJson(json).accessToken, isNull);
  });

  test('without a key nothing is written, rather than written in clear', () {
    RecordSeal.debugKey = null;
    expect(_record.toJson, throwsStateError);
  });

  group('load', () {
    setUp(() {
      RecordSeal.debugKey = null;
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('the app creates the key once and the workers find it', () async {
      const storage = FlutterSecureStorage();
      expect(await RecordSeal.load(storage), isFalse);
      expect(RecordSeal.ready, isFalse);

      expect(await RecordSeal.load(storage, create: true), isTrue);
      final sealed = jsonEncode(_record.toJson());

      // A worker isolate: same store, no key in memory yet.
      RecordSeal.debugKey = null;
      expect(await RecordSeal.load(storage), isTrue);
      final read = BackgroundTokenRecord.fromJson(
        jsonDecode(sealed) as Map<String, Object?>,
      );
      expect(read.refreshToken, 'secret-refresh');
    });
  });
}

extension on BackgroundTokenRecord {
  Map<String, Object?> toJsonForTest() => {
    'gen': gen,
    'authType': authType,
    'endpoint': endpoint,
    'identityEpoch': identityEpoch,
    'catalogServerId': catalogServerId,
    'originalRefreshToken': originalRefreshToken,
    'notificationSessionId': notificationSessionId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'password': password,
    'basicCredential': basicCredential,
    'simpleCookie': simpleCookie,
    'extraHeaders': extraHeaders,
  };
}
