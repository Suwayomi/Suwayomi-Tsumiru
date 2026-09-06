// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Tests for the generic custom HTTP headers (e.g. Cloudflare Zero Trust).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/auth/data/secure_credentials_provider.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/features/onboarding/data/server_resolver.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  _InMemorySecureStorage([Map<String, String>? seed]) : _store = {...?seed};
  final Map<String, String> _store;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void main() {
  group('applyCustomHeaders', () {
    test('merges custom headers into an empty base', () {
      final out = applyCustomHeaders({}, {
        'CF-Access-Client-Id': 'id123',
        'CF-Access-Client-Secret': 's3cret',
      });
      expect(out, {
        'CF-Access-Client-Id': 'id123',
        'CF-Access-Client-Secret': 's3cret',
      });
    });

    test('never overwrites Authorization or Cookie (any case)', () {
      final out = applyCustomHeaders(
        {'Authorization': 'Bearer abc', 'Cookie': 'JSESSIONID=x'},
        {'authorization': 'Basic evil', 'COOKIE': 'evil=y', 'X-Custom': 'ok'},
      );
      expect(out['Authorization'], 'Bearer abc');
      expect(out['Cookie'], 'JSESSIONID=x');
      expect(out['X-Custom'], 'ok');
      expect(out.containsKey('authorization'), isFalse);
    });

    test('null/empty custom is a no-op returning the same map', () {
      final base = <String, String>{'a': 'b'};
      expect(identical(applyCustomHeaders(base, null), base), isTrue);
      expect(identical(applyCustomHeaders(base, const {}), base), isTrue);
    });
  });

  group('applyIsolateCustomHeaders', () {
    test('same auth-header protection in isolates', () {
      final out = applyIsolateCustomHeaders(
        {'Authorization': 'Bearer abc'},
        {'Authorization': 'evil', 'CF-Access-Client-Id': 'id'},
      );
      expect(out['Authorization'], 'Bearer abc');
      expect(out['CF-Access-Client-Id'], 'id');
    });
  });

  group('validateCustomHeaderName', () {
    test('accepts typical proxy headers', () {
      expect(validateCustomHeaderName('CF-Access-Client-Id'), isNull);
      expect(validateCustomHeaderName('X-Custom-Auth'), isNull);
    });

    test('rejects empty / spaced / colon names', () {
      expect(validateCustomHeaderName(''), isNotNull);
      expect(validateCustomHeaderName('   '), isNotNull);
      expect(validateCustomHeaderName('Bad Name'), isNotNull);
      expect(validateCustomHeaderName('Bad:Name'), isNotNull);
    });
  });

  group('CustomHttpHeadersStore.decode', () {
    test('round-trips through encode', () {
      const headers = {
        'CF-Access-Client-Id': 'id',
        'CF-Access-Client-Secret': 'secret',
      };
      final raw = CustomHttpHeadersStore.encode(headers);
      expect(CustomHttpHeadersStore.decode(raw), headers);
    });

    test('malformed input reads as empty, never throws', () {
      expect(CustomHttpHeadersStore.decode(null), isEmpty);
      expect(CustomHttpHeadersStore.decode(''), isEmpty);
      expect(CustomHttpHeadersStore.decode('not-json'), isEmpty);
      expect(CustomHttpHeadersStore.decode('[1,2]'), isEmpty);
    });
  });

  group('server_resolver extraHeaders', () {
    test('probeServer sends extra headers on both probe requests', () async {
      final seen = <Map<String, String>>[];
      final client = MockClient((request) async {
        seen.add(Map<String, String>.from(request.headers));
        if (request.body.contains('aboutServer')) {
          return http.Response(
            '{"data":{"aboutServer":{"name":"S","version":"1"}}}',
            200,
          );
        }
        return http.Response(
          '{"data":{"downloadStatus":{"__typename":"x"}}}',
          200,
        );
      });
      final result = await probeServer(
        'http://192.168.0.10:4567',
        client: client,
        extraHeaders: const {'CF-Access-Client-Id': 'id123'},
      );
      expect(result.confirmed, isTrue);
      expect(seen, hasLength(2));
      for (final h in seen) {
        expect(h['CF-Access-Client-Id'], 'id123');
      }
    });

    test('probeServer still works without extra headers', () async {
      final client = MockClient((request) async {
        expect(request.headers.containsKey('CF-Access-Client-Id'), isFalse);
        return http.Response(
          '{"data":{"aboutServer":{"name":"S","version":"1"}}}',
          200,
        );
      });
      final result = await probeServer(
        'http://192.168.0.10:4567',
        client: client,
      );
      expect(result.confirmed, isTrue);
    });
  });

  group('BackgroundTokenRecord extraHeaders', () {
    test('round-trips through JSON', () {
      const record = BackgroundTokenRecord(
        gen: 0,
        authType: 'none',
        extraHeaders: {'CF-Access-Client-Id': 'id'},
      );
      final revived = BackgroundTokenRecord.fromJson(record.toJson());
      expect(revived.extraHeaders, {'CF-Access-Client-Id': 'id'});
    });

    test('missing key defaults to empty (old payloads)', () {
      final revived = BackgroundTokenRecord.fromJson(const {
        'gen': 0,
        'authType': 'none',
      });
      expect(revived.extraHeaders, isEmpty);
    });
  });

  group('CustomHttpHeadersStore — secure-storage persistence', () {
    ProviderContainer containerWith(_InMemorySecureStorage storage) =>
        ProviderContainer(overrides: [
          secureStorageProvider.overrideWithValue(storage),
        ]);

    test('empty storage loads as empty', () async {
      final container = containerWith(_InMemorySecureStorage());
      addTearDown(container.dispose);
      await expectLater(
        container.read(customHttpHeadersProvider.future),
        completion(isEmpty),
      );
    });

    test('put persists and a fresh container reloads it', () async {
      final storage = _InMemorySecureStorage();
      final container = containerWith(storage);
      addTearDown(container.dispose);
      await container.read(customHttpHeadersProvider.future);
      await container
          .read(customHttpHeadersProvider.notifier)
          .put('CF-Access-Client-Id', 'id123');
      expect(
        container.read(customHttpHeadersProvider).value,
        {'CF-Access-Client-Id': 'id123'},
      );

      final reloaded = containerWith(storage);
      addTearDown(reloaded.dispose);
      await expectLater(
        reloaded.read(customHttpHeadersProvider.future),
        completion({'CF-Access-Client-Id': 'id123'}),
      );
    });

    test('remove and clear delete from storage', () async {
      final storage = _InMemorySecureStorage();
      final container = containerWith(storage);
      addTearDown(container.dispose);
      final store = container.read(customHttpHeadersProvider.notifier);
      await container.read(customHttpHeadersProvider.future);
      await store.put('X-A', '1');
      await store.put('X-B', '2');
      await store.remove('X-A');
      expect(
        container.read(customHttpHeadersProvider).value,
        {'X-B': '2'},
      );
      await store.clear();
      expect(
        container.read(customHttpHeadersProvider).value,
        isEmpty,
      );
      expect(storage._store.containsKey(CustomHttpHeadersStore.secureKey),
          isFalse);
    });

    test('setAll replaces the entire map in storage', () async {
      final storage = _InMemorySecureStorage();
      final container = containerWith(storage);
      addTearDown(container.dispose);
      final store = container.read(customHttpHeadersProvider.notifier);
      await container.read(customHttpHeadersProvider.future);
      await store.setAll({'X-First': '1', 'X-Second': '2'});
      expect(
        container.read(customHttpHeadersProvider).value,
        {'X-First': '1', 'X-Second': '2'},
      );

      final reloaded = containerWith(storage);
      addTearDown(reloaded.dispose);
      await expectLater(
        reloaded.read(customHttpHeadersProvider.future),
        completion({'X-First': '1', 'X-Second': '2'}),
      );
    });
  });
}
