import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tsumiru/src/features/auth/data/pending_tracker_oauth_store_io.dart';

void main() {
  late String path;
  setUp(() async {
    path =
        '${(await Directory.systemTemp.createTemp('oauth-sql-test-')).path}/pending.sqlite';
  });
  test('read and cancellation do not create an absent database', () async {
    final store = SqlitePendingTrackerOAuthStore(path: path);
    expect(await store.read(), isNull);
    expect(await store.cancel(), isTrue);
    expect(await File(path).exists(), isFalse);
  });
  test('two connections commit exactly one claim of the same record', () async {
    final a = SqlitePendingTrackerOAuthStore(path: path);
    final b = SqlitePendingTrackerOAuthStore(path: path);
    const payload = '{"nonce":"a","origin":"account"}';
    expect(await a.replace(payload), isTrue);
    final claims = await Future.wait([a.claim(payload), b.claim(payload)]);
    expect(claims.where((claimed) => claimed), hasLength(1));
    expect(await a.read(), isNull);
    expect(await b.read(), isNull);
  });
  test(
    'stale claim and conditional clear leave a replacement request intact',
    () async {
      final a = SqlitePendingTrackerOAuthStore(path: path);
      final b = SqlitePendingTrackerOAuthStore(path: path);
      const old = '{"nonce":"a","origin":"account"}';
      const replacement = '{"nonce":"b","origin":"account"}';
      await a.replace(old);
      await b.replace(replacement);
      expect(await a.claim(old), isFalse);
      expect(await a.clearIfNonce('a'), isFalse);
      expect(await b.read(), replacement);
      expect(await b.clearIfNonce('b'), isTrue);
      expect(await a.read(), isNull);
    },
  );
  test(
    'a held writer lock fails closed without changing the pending record',
    () async {
      final store = SqlitePendingTrackerOAuthStore(path: path);
      const payload = '{"nonce":"a"}';
      await store.replace(payload);
      final held = sqlite3.open(path);
      held.execute('BEGIN IMMEDIATE');
      try {
        expect(await store.claim(payload), isFalse);
        expect(await store.cancel(), isFalse);
        expect(await store.replace('{"nonce":"b"}'), isFalse);
      } finally {
        held.execute('ROLLBACK');
        held.close();
      }
      expect(await store.read(), payload);
    },
  );
  test(
    'unavailable database storage rejects changes and cancellation',
    () async {
      await File(path).writeAsString('not a directory');
      final store = SqlitePendingTrackerOAuthStore(path: '$path/child.sqlite');
      expect(await store.replace('{"nonce":"a"}'), isFalse);
      expect(await store.cancel(), isFalse);
      await expectLater(store.read(), throwsA(isA<FileSystemException>()));
    },
  );
}
