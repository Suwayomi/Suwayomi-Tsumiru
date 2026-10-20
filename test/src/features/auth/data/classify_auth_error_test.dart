import 'dart:io' show HandshakeException;

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/basic_credentials_rejected.dart';
import 'package:tsumiru/src/features/auth/data/simple_login_client.dart';

void main() {
  group('classifyAuthError', () {
    test('classifies each auth failure', () {
      // Must not fall through to the generic "is your URL pointing at the
      // Suwayomi API?", which says nothing when the password is simply wrong.
      expect(
        classifyAuthError(const BasicCredentialsRejected()).kind,
        TestConnectionFailureKind.invalidCredentials,
      );
      expect(
        classifyAuthError(
          const HandshakeException('Wrong version number'),
        ).kind,
        TestConnectionFailureKind.tls,
      );
      expect(
        classifyAuthError(
          Exception('SocketException: Failed host lookup: foo.bar'),
        ).kind,
        TestConnectionFailureKind.network,
      );
      // An unverified browser session is not labelled a wrong password.
      expect(
        classifyAuthError(const SimpleLoginSessionFailure()).kind,
        TestConnectionFailureKind.browserSession,
      );
    });
  });
}
