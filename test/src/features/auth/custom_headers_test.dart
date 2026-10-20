// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Tests for the generic custom HTTP headers (e.g. Cloudflare Zero Trust).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/custom_headers_store.dart';

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

  test('validation rejects bad names and decode never throws', () {
    expect(validateCustomHeaderName(''), isNotNull);
    expect(validateCustomHeaderName('   '), isNotNull);
    expect(validateCustomHeaderName('Bad Name'), isNotNull);
    expect(validateCustomHeaderName('Bad:Name'), isNotNull);

    expect(CustomHttpHeadersStore.decode(null), isEmpty);
    expect(CustomHttpHeadersStore.decode(''), isEmpty);
    expect(CustomHttpHeadersStore.decode('not-json'), isEmpty);
    expect(CustomHttpHeadersStore.decode('[1,2]'), isEmpty);
  });

  group('server_resolver extraHeaders', () {});

  group('CustomHttpHeadersStore — secure-storage persistence', () {});
}
