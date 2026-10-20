// Copyright (c) 2026 Contributors to the Suwayomi project

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';

void main() {
  test('a real cookie is sent as a Cookie header', () {
    const state = AuthCredentialsState(simpleLoginCookie: 'JSESSIONID=abc');
    expect(state.simpleLoginCookieHeader, {'Cookie': 'JSESSIONID=abc'});
  });
}
