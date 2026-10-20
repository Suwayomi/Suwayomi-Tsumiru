import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';

void main() {
  group('isLocalAddress', () {
    test('private and loopback ranges are local', () {
      for (final url in [
        'http://localhost',
        'http://localhost:4567',
        'http://LOCALHOST:4567/api',
        'http://127.0.0.1',
        'http://127.0.0.1:8080/api/graphql',
        'http://127.255.255.255',
        'http://192.168.0.10:4568',
        'http://192.168.0.1',
        'http://10.0.0.1',
        'http://10.255.255.255',
        'http://172.16.0.1',
        'http://172.20.50.50',
        'http://172.31.255.255',
      ]) {
        expect(isLocalAddress(url), isTrue, reason: url);
      }
    });

    test('public and malformed addresses are not local', () {
      for (final url in [
        // 172.15 and 172.32 are outside the private range.
        'http://172.15.0.1',
        'http://172.32.0.1',
        'http://manga.example.com',
        'https://example.com',
        'http://8.8.8.8',
        'http://1.1.1.1',
        '',
        'not a url',
        'http://',
        'http://999.999.999.999',
      ]) {
        expect(isLocalAddress(url), isFalse, reason: url);
      }
    });
  });
}
