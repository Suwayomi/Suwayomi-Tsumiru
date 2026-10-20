// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Tests for the generic custom HTTP headers (e.g. Cloudflare Zero Trust).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('applyCustomHeaders', () {
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
  });

  group('applyIsolateCustomHeaders', () {});

  group('validateCustomHeaderName', () {
    test('rejects empty / spaced / colon names', () {
      expect(validateCustomHeaderName(''), isNotNull);
      expect(validateCustomHeaderName('   '), isNotNull);
      expect(validateCustomHeaderName('Bad Name'), isNotNull);
      expect(validateCustomHeaderName('Bad:Name'), isNotNull);
    });
  });

  group('CustomHttpHeadersStore.decode', () {
    test('malformed input reads as empty, never throws', () {
      expect(CustomHttpHeadersStore.decode(null), isEmpty);
      expect(CustomHttpHeadersStore.decode(''), isEmpty);
      expect(CustomHttpHeadersStore.decode('not-json'), isEmpty);
      expect(CustomHttpHeadersStore.decode('[1,2]'), isEmpty);
    });
  });

  group('server_resolver extraHeaders', () {});

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
  });

  group('CustomHttpHeadersStore — secure-storage persistence', () {});
}
