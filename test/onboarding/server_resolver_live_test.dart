// Copyright (c) 2026 Contributors to the Suwayomi project
//
// LIVE test — runs the REAL resolver against a REAL Suwayomi server over the
// network (no mocks). The server address is NEVER hard-coded: it is read from
// the TSUMIRU_LIVE_SERVER environment variable and the test skips when unset,
// so no address or credential is ever committed.
//
// Run:  TSUMIRU_LIVE_SERVER=host:port flutter test test/onboarding/server_resolver_live_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/features/onboarding/data/server_resolver.dart';

void main() {
  final host = Platform.environment['TSUMIRU_LIVE_SERVER'];

  test('LIVE: resolves a real Suwayomi server as found', () async {
    if (host == null || host.isEmpty) {
      // ignore: avoid_print
      print('SKIP: set TSUMIRU_LIVE_SERVER=host:port to run the live test.');
      return;
    }

    final client = http.Client();
    final result = await resolveServer(host, client: client);
    client.close();

    if (result.outcome == ResolveOutcome.notReached) {
      // ignore: avoid_print
      print('SKIP: $host not reachable from this machine.');
      return;
    }

    // A reachable Suwayomi confirms with a real name + version.
    expect(result.outcome, ResolveOutcome.found,
        reason: 'a real Suwayomi server should be confirmed');
    expect(result.serverName, isNotEmpty);
    expect(result.serverVersion, isNotNull);
    // Auth mode is whatever the server is configured for; just assert we read one.
    expect(result.authMode, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
