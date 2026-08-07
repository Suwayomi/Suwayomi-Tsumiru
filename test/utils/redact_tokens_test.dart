import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/crash/redact_tokens.dart';

void main() {
  group('redactTokens', () {
    test('redacts token / accessToken / access_token / refresh variants', () {
      expect(redactTokens('x?token=ABC.def'), 'x?token=<redacted>');
      expect(redactTokens('x&accessToken=ABC'), 'x&accessToken=<redacted>');
      expect(redactTokens('x?access_token=ABC'), 'x?access_token=<redacted>');
      expect(redactTokens('x&refreshToken=ABC'), 'x&refreshToken=<redacted>');
      expect(redactTokens('x?refresh_token=ABC'), 'x?refresh_token=<redacted>');
    });

    test('is case-insensitive on the key, preserving original casing', () {
      expect(redactTokens('x?Token=ABC'), 'x?Token=<redacted>');
      expect(redactTokens('x&AccessToken=ABC'), 'x&AccessToken=<redacted>');
    });

    test('stops at value delimiters and preserves the rest', () {
      expect(redactTokens('a?token=ABC&width=100'),
          'a?token=<redacted>&width=100');
      expect(redactTokens('a?width=100&token=ABC'),
          'a?width=100&token=<redacted>');
      expect(redactTokens('a?token=ABC;b=2'), 'a?token=<redacted>;b=2');
      expect(redactTokens('GET http://h/img?token=ey.J.Z failed'),
          'GET http://h/img?token=<redacted> failed');
    });

    test('does not over-redact non-token params or plain text', () {
      expect(redactTokens('a?width=100&height=200'), 'a?width=100&height=200');
      expect(redactTokens('no tokens here'), 'no tokens here');
      // Not a query param (no ? or & immediately before the key).
      expect(redactTokens('the mytoken value'), 'the mytoken value');
    });

    test('redacts every occurrence', () {
      expect(redactTokens('a?token=X then b?token=Y'),
          'a?token=<redacted> then b?token=<redacted>');
    });

    test('redacts token-bearing entries in a multi-line historical log', () {
      // Simulates a pre-redaction crash log entry still on disk.
      const log = '[2026-01-01] Exception: http://h/img?token=OLD.secret x\n\n'
          '[2026-02-01] StateError: unrelated failure\n\n';
      final out = redactTokens(log);
      expect(out.contains('OLD.secret'), isFalse);
      expect(out.contains('token=<redacted>'), isTrue);
      expect(out.contains('StateError: unrelated failure'), isTrue);
    });
  });
}
