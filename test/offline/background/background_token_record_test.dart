import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

void main() {
  const owner = BackgroundTokenRecord(
    gen: 1,
    authType: 'uiLogin',
    endpoint: 'https://server',
    accessToken: 'A',
    refreshToken: 'refresh-a',
    identityEpoch: 4,
    catalogServerId: 'account-a',
    originalRefreshToken: 'refresh-a',
  );
  const other = BackgroundTokenRecord(
    gen: 2,
    authType: 'uiLogin',
    endpoint: 'https://server',
    accessToken: 'B',
    refreshToken: 'refresh-b',
    identityEpoch: 5,
    catalogServerId: 'account-b',
    originalRefreshToken: 'refresh-b',
  );

  test('a newer record gen is used WITHOUT calling refresh', () async {
    var record = const BackgroundTokenRecord(
      gen: 1,
      authType: 'uiLogin',
      accessToken: 'OLD',
      refreshToken: 'R0',
    );
    var refreshCalls = 0;
    final broker = TokenBroker(
      read: () async => record,
      write: (r) async => record = r,
      refreshFn: (_) async {
        refreshCalls++;
        return (tokens: (access: 'NEW', refresh: 'R1'), transient: false);
      },
    );
    // someone else already advanced the record:
    record = const BackgroundTokenRecord(
      gen: 2,
      authType: 'uiLogin',
      accessToken: 'NEWER',
      refreshToken: 'R9',
    );
    final token = await broker.resolveAfter401('OLD');
    expect(token, 'NEWER');
    expect(refreshCalls, 0);
  });

  test('refresh rotates BOTH tokens and bumps gen', () async {
    var record = const BackgroundTokenRecord(
      gen: 1,
      authType: 'uiLogin',
      accessToken: 'OLD',
      refreshToken: 'R0',
    );
    final broker = TokenBroker(
      read: () async => record,
      write: (r) async => record = r,
      refreshFn: (rt) async {
        expect(rt, 'R0');
        return (tokens: (access: 'NEW', refresh: 'R1'), transient: false);
      },
    );
    final token = await broker.resolveAfter401('OLD');
    expect(token, 'NEW');
    expect(record.gen, 2);
    expect(record.accessToken, 'NEW');
    expect(record.refreshToken, 'R1'); // rotated refresh persisted (fixes C4)
  });

  test('a dead refresh returns null and is not marked transient', () async {
    var record = const BackgroundTokenRecord(
      gen: 1,
      authType: 'uiLogin',
      accessToken: 'OLD',
      refreshToken: 'R0',
    );
    final broker = TokenBroker(
      read: () async => record,
      write: (r) async => record = r,
      refreshFn: (_) async => (tokens: null, transient: false),
    );
    expect(await broker.resolveAfter401('OLD'), isNull);
    expect(broker.lastRefreshTransient, isFalse);
  });

  test(
    'a refresh that could not reach the server is marked transient',
    () async {
      var record = const BackgroundTokenRecord(
        gen: 1,
        authType: 'uiLogin',
        accessToken: 'OLD',
        refreshToken: 'R0',
      );
      final broker = TokenBroker(
        read: () async => record,
        write: (r) async => record = r,
        refreshFn: (_) async => (tokens: null, transient: true),
      );
      expect(await broker.resolveAfter401('OLD'), isNull);
      expect(broker.lastRefreshTransient, isTrue);
    },
  );
  test('identity proof survives serialization and token rotation', () {
    final rotated = owner.copyWith(
      gen: 2,
      accessToken: 'A2',
      refreshToken: 'rotated',
    );
    final restored = BackgroundTokenRecord.fromJson(rotated.toJson());
    expect(restored.sameIdentity(owner), isTrue);
    expect(restored.identityEpoch, 4);
    expect(restored.catalogServerId, 'account-a');
    expect(restored.originalRefreshToken, 'refresh-a');
    expect(restored.refreshToken, 'rotated');
    expect(restored.sameIdentity(other), isFalse);
  });

  test(
    'same endpoint account replacement is rejected before refresh',
    () async {
      var calls = 0;
      final broker = TokenBroker(
        expectedIdentity: owner,
        read: () async => other,
        write: (_) async {
          fail('must not write');
        },
        refreshFn: (_) async {
          calls++;
          return (
            tokens: (access: 'new', refresh: 'new-refresh'),
            transient: false,
          );
        },
      );
      broker.lastRefreshTransient = true;
      expect(await broker.resolveAfter401('A'), isNull);
      expect(calls, 0);
      expect(broker.lastRefreshTransient, isFalse);
    },
  );

  test(
    'account replacement while refreshing cannot adopt or return tokens',
    () async {
      var record = owner;
      final started = Completer<void>();
      final response = Completer<RefreshAttempt>();
      var writes = 0;
      final broker = TokenBroker(
        expectedIdentity: owner,
        read: () async => record,
        write: (value) async {
          writes++;
          record = value;
        },
        refreshFn: (_) {
          started.complete();
          return response.future;
        },
      );
      final pending = broker.resolveAfter401('A');
      await started.future;
      record = other;
      response.complete((
        tokens: (access: 'A2', refresh: 'refresh-a2'),
        transient: false,
      ));
      expect(await pending, isNull);
      expect(writes, 0);
      expect(record, same(other));
      expect(broker.lastRefreshTransient, isFalse);
    },
  );

  test('same account refresh preserves original ownership proof', () async {
    var record = owner;
    final broker = TokenBroker(
      expectedIdentity: owner,
      read: () async => record,
      write: (value) async {
        record = value;
      },
      refreshFn: (_) async =>
          (tokens: (access: 'A2', refresh: 'refresh-a2'), transient: false),
    );
    expect(await broker.resolveAfter401('A'), 'A2');
    expect(record.sameIdentity(owner), isTrue);
    expect(record.originalRefreshToken, 'refresh-a');
    expect(record.refreshToken, 'refresh-a2');
  });
  test('each ownership field must match independently', () {
    for (final changed in <String, Object>{
      'authType': 'none',
      'endpoint': 'https://other',
      'identityEpoch': 9,
      'catalogServerId': 'different-catalogue',
      'originalRefreshToken': 'different-refresh',
    }.entries) {
      final json = owner.toJson()..[changed.key] = changed.value;
      expect(
        owner.sameIdentity(BackgroundTokenRecord.fromJson(json)),
        isFalse,
        reason: changed.key,
      );
    }
  });

  group('refreshIfDue', () {
    final now = DateTime.utc(2026, 9, 26, 12);
    String jwt(Duration expIn) {
      String part(Object json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final exp = now.add(expIn).millisecondsSinceEpoch ~/ 1000;
      return '${part({'alg': 'HS256'})}.${part({'exp': exp})}.sig';
    }

    late BackgroundTokenRecord stored;
    late int refreshCalls;
    late Completer<void>? gate;
    late RefreshAttempt attempt;
    TokenBroker broker() => TokenBroker(
      read: () async => stored,
      write: (r) async => stored = r,
      refreshFn: (_) async {
        refreshCalls++;
        await gate?.future;
        return attempt;
      },
    );
    BackgroundTokenRecord withAccess(String access) => BackgroundTokenRecord(
      gen: 1,
      authType: 'uiLogin',
      accessToken: access,
      refreshToken: 'R',
    );

    setUp(() {
      refreshCalls = 0;
      gate = null;
      attempt = (tokens: (access: 'NEW', refresh: 'R'), transient: false);
    });

    test('refreshes an expired token before the request', () async {
      stored = withAccess(jwt(const Duration(hours: -3)));
      final b = broker();
      final used = await b.refreshIfDue(stored, now: now);
      expect(refreshCalls, 1);
      expect(used.accessToken, 'NEW');
      expect(used.gen, 2);
      expect(b.latest?.accessToken, 'NEW');
    });

    test('refreshes a token inside the lead, leaves a fresh one alone',
        () async {
      stored = withAccess(jwt(const Duration(seconds: 30)));
      expect((await broker().refreshIfDue(stored, now: now)).accessToken, 'NEW');
      refreshCalls = 0;
      final fresh = withAccess(jwt(const Duration(minutes: 4)));
      stored = fresh;
      expect(await broker().refreshIfDue(fresh, now: now), same(fresh));
      expect(refreshCalls, 0);
    });

    test('leaves opaque tokens and other auth modes to the 401 path',
        () async {
      stored = withAccess('opaque');
      expect(await broker().refreshIfDue(stored, now: now), same(stored));
      const basic = BackgroundTokenRecord(gen: 1, authType: 'basic');
      expect(await broker().refreshIfDue(basic, now: now), same(basic));
      expect(refreshCalls, 0);
    });

    test('parallel callers share one refresh', () async {
      stored = withAccess(jwt(const Duration(hours: -1)));
      gate = Completer<void>();
      final b = broker();
      final calls = [
        for (var i = 0; i < 5; i++) b.refreshIfDue(stored, now: now),
      ];
      await pumpEventQueue();
      gate!.complete();
      final used = await Future.wait(calls);
      expect(refreshCalls, 1);
      expect(used.map((r) => r.accessToken).toSet(), {'NEW'});
    });

    test('a failed refresh answers the next 401 without calling again',
        () async {
      final expired = jwt(const Duration(hours: -1));
      stored = withAccess(expired);
      attempt = (tokens: null, transient: true);
      final b = broker();
      expect(await b.refreshIfDue(stored, now: now), same(stored));
      expect(await b.resolveAfter401(expired), isNull);
      expect(b.lastRefreshTransient, isTrue);
      expect(refreshCalls, 1);
    });
  });
}
