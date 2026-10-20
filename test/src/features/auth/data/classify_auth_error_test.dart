import 'dart:io' show HandshakeException;

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/basic_credentials_rejected.dart';
import 'package:tsumiru/src/features/auth/data/simple_login_client.dart';

void main() {
  group('classifyAuthError', () {
    // Must not fall through to the generic "is your URL pointing at the
    // Suwayomi API?", which says nothing when the password is simply wrong.
    test('BasicCredentialsRejected → invalidCredentials', () {
      expect(
        classifyAuthError(const BasicCredentialsRejected()).kind,
        TestConnectionFailureKind.invalidCredentials,
      );
    });

    test('HandshakeException → tls', () {
      final result = classifyAuthError(
        const HandshakeException('Wrong version number'),
      );
      expect(result.kind, TestConnectionFailureKind.tls);
    });

    test('SocketException-shaped error → network (not tls)', () {
      final result = classifyAuthError(
        Exception('SocketException: Failed host lookup: foo.bar'),
      );
      expect(result.kind, TestConnectionFailureKind.network);
    });

    test('unverified browser session is not labelled a wrong password', () {
      expect(
        classifyAuthError(const SimpleLoginSessionFailure()).kind,
        TestConnectionFailureKind.browserSession,
      );
    });
  });
}
