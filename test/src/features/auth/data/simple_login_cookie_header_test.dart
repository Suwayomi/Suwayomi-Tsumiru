// Copyright (c) 2026 Contributors to the Suwayomi project

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/auth/data/simple_login_client.dart';

void main() {
  test('a real cookie is sent as a Cookie header', () {
    const state = AuthCredentialsState(simpleLoginCookie: 'JSESSIONID=abc');
    expect(state.simpleLoginCookieHeader, {'Cookie': 'JSESSIONID=abc'});
  });

  test('a browser-managed session sends no Cookie header', () {
    const state = AuthCredentialsState(
      simpleLoginCookie: kBrowserManagedSimpleSession,
    );
    expect(state.simpleLoginCookieHeader, isNull);
  });
}
