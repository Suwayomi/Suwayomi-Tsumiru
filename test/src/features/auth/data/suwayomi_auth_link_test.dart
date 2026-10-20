// Copyright (c) 2026 Contributors to the Suwayomi project

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/auth/data/suwayomi_auth_link.dart';

/// Records each downstream request and lets the test script the responses
/// it returns. The next-in-link, after the SuwayomiAuthLink.
class _RecorderLink extends Link {
  _RecorderLink(this.responses);
  final List<Response Function(Request)> responses;
  int callCount = 0;
  final List<Request> received = [];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    received.add(request);
    final fn = responses[callCount.clamp(0, responses.length - 1)];
    callCount++;
    yield fn(request);
  }
}

Response _ok() => Response(data: {'ok': true}, response: {});

Response _unauthorized() => Response(
  data: null,
  errors: [
    const GraphQLError(
      message: 'Unauthorized',
      extensions: {
        'http': {'status': 401},
      },
    ),
  ],
  response: {},
);

Request _req() =>
    Request(operation: Operation(document: parseString('query Q { x }')));

void main() {
  group('SuwayomiAuthLink — UI Login', () {
    test('injects Authorization: Bearer header from store', () async {
      final recorder = _RecorderLink([(_) => _ok()]);
      String? lastAuth;
      final link = SuwayomiAuthLink(
        authType: () => AuthType.uiLogin,
        getHeaders: () async => {'Authorization': 'Bearer TOK'},
        refreshAccessToken: () async => const RefreshAuthFailure(),
        onNeedsReauth: () {},
      );

      await for (final _ in link.concat(recorder).request(_req())) {}

      lastAuth = recorder.received.last.context
          .entry<HttpLinkHeaders>()
          ?.headers['Authorization'];
      expect(lastAuth, 'Bearer TOK');
    });

    test('on 401, calls refresh and retries with new token (header asserts'
        ' the retry uses FRESH, not STALE — R2-9)', () async {
      int refreshCalls = 0;
      final recorder = _RecorderLink([
        (_) => _unauthorized(), // first call: 401
        (_) => _ok(), // second call (after refresh): ok
      ]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.uiLogin,
        getHeaders: () async => {'Authorization': 'Bearer STALE'},
        refreshAccessToken: () async {
          refreshCalls++;
          return const RefreshSuccess('FRESH');
        },
        onNeedsReauth: () {},
      );

      Response? lastResponse;
      await for (final r in link.concat(recorder).request(_req())) {
        lastResponse = r;
      }

      expect(refreshCalls, 1);
      expect(recorder.callCount, 2);
      expect(lastResponse?.data, {'ok': true});
      // R2-9: the retried request MUST use the fresh token, not the stale
      // one. A broken implementation that retried with STALE would pass
      // the previous version of this test because the second scripted
      // response is _ok() regardless of header.
      expect(
        recorder.received[0].context
            .entry<HttpLinkHeaders>()
            ?.headers['Authorization'],
        'Bearer STALE',
        reason: 'first request uses the stale token before refresh',
      );
      expect(
        recorder.received[1].context
            .entry<HttpLinkHeaders>()
            ?.headers['Authorization'],
        'Bearer FRESH',
        reason: 'second request MUST use the freshly-refreshed token',
      );
    });

    // Note: process-wide single-flight is now an AuthCoordinator concern,
    // not the Link's (R2-3). See AuthCoordinator tests for the dedup
    // assertion; the Link itself just calls `refreshAccessToken` once per
    // 401 it sees, and trusts the coordinator to handle concurrency.
  });

  group('SuwayomiAuthLink — Simple Login', () {
    test('injects Cookie header from store', () async {
      final recorder = _RecorderLink([(_) => _ok()]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.simpleLogin,
        getHeaders: () async => {'Cookie': 'JSESSIONID=abc'},
        refreshAccessToken: () async => const RefreshAuthFailure(),
        onNeedsReauth: () {},
      );

      await for (final _ in link.concat(recorder).request(_req())) {}

      final cookie = recorder.received.last.context
          .entry<HttpLinkHeaders>()
          ?.headers['Cookie'];
      expect(cookie, 'JSESSIONID=abc');
    });
  });
}
