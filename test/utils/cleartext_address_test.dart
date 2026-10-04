// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/utils/network/cleartext_address.dart';

void main() {
  test('plain HTTP to an internet host sends credentials in clear', () {
    for (final url in [
      'http://suwayomi.example.net',
      'http://suwayomi.example.net:4567/',
      'HTTP://Example.COM',
      'http://8.8.8.8:4567',
      'http://172.32.0.1',
      'http://[2001:db8::1]:4567',
    ]) {
      expect(sendsCredentialsInClear(url), isTrue, reason: url);
    }
  });

  test('HTTPS is never flagged', () {
    expect(sendsCredentialsInClear('https://suwayomi.example.net'), isFalse);
  });

  test('plain HTTP on a private or local network is not flagged', () {
    for (final url in [
      'http://192.168.1.100:4567',
      'http://10.0.0.5',
      'http://172.16.0.1',
      'http://172.31.255.255',
      'http://127.0.0.1:4567',
      'http://169.254.10.10',
      'http://100.101.102.103', // Tailscale
      'http://localhost:4567',
      'http://nas:4567',
      'http://nas.local',
      'http://server.lan',
      'http://server.home.arpa',
      'http://[::1]:4567',
      'http://[fd12:3456::1]',
      'http://[fe80::1]',
    ]) {
      expect(sendsCredentialsInClear(url), isFalse, reason: url);
    }
  });

  test('an empty or unparseable address is not flagged', () {
    expect(sendsCredentialsInClear(''), isFalse);
    expect(sendsCredentialsInClear('not a url'), isFalse);
    expect(sendsCredentialsInClear('http://'), isFalse);
  });
}
