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

    test('arbitrary error mentioning "handshake" → tls', () {
      final result = classifyAuthError(
        Exception('OperationException: handshake failed during fetch'),
      );
      expect(result.kind, TestConnectionFailureKind.tls);
    });

    test('error mentioning "certificate" → tls', () {
      final result = classifyAuthError(
        Exception('Bad certificate from server'),
      );
      expect(result.kind, TestConnectionFailureKind.tls);
    });

    test('SocketException-shaped error → network (not tls)', () {
      final result = classifyAuthError(
        Exception('SocketException: Failed host lookup: foo.bar'),
      );
      expect(result.kind, TestConnectionFailureKind.network);
    });

    test('timeout → network', () {
      final result = classifyAuthError(
        Exception('TimeoutException: Future not completed'),
      );
      expect(result.kind, TestConnectionFailureKind.network);
    });

    test('unauthorized → invalidCredentials', () {
      final result = classifyAuthError(Exception('401 Unauthorized'));
      expect(result.kind, TestConnectionFailureKind.invalidCredentials);
    });

    test('SimpleLoginAuthFailure → invalidCredentials', () {
      final result = classifyAuthError(SimpleLoginAuthFailure());
      expect(result.kind, TestConnectionFailureKind.invalidCredentials);
    });

    test('unverified browser session is not labelled a wrong password', () {
      expect(
        classifyAuthError(const SimpleLoginSessionFailure()).kind,
        TestConnectionFailureKind.browserSession,
      );
    });

    test('SimpleLoginShapeFailure → unexpectedShape (with detail)', () {
      final result = classifyAuthError(SimpleLoginShapeFailure('odd body'));
      expect(result.kind, TestConnectionFailureKind.unexpectedShape);
      expect(result.detail, 'odd body');
    });

    test('unknown error → unexpectedShape (with detail)', () {
      final result = classifyAuthError(Exception('mystery boom'));
      expect(result.kind, TestConnectionFailureKind.unexpectedShape);
      expect(result.detail, contains('mystery boom'));
    });

    test('TLS check beats network keyword collision', () {
      // HandshakeException's toString contains "connection" via context.
      // We want tls classification to win, not network.
      final result = classifyAuthError(
        Exception('TLS handshake error while opening connection'),
      );
      expect(result.kind, TestConnectionFailureKind.tls);
    });
  });
}
