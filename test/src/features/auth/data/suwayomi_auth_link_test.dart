// Copyright (c) 2026 Contributors to the Suwayomi project

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
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

/// Like `_RecorderLink` but emits multiple events for a single request —
/// used to verify subscription-style streams aren't truncated by the
/// auth link's first-event inspection.
class _MultiEventLink extends Link {
  _MultiEventLink(this.events);
  final List<Response> events;
  int callCount = 0;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    callCount++;
    for (final e in events) {
      yield e;
    }
  }
}

Response _ok() => Response(data: {'ok': true}, response: {});

Response _unauthorized() => Response(
      data: null,
      errors: [
        const GraphQLError(message: 'Unauthorized', extensions: {
          'http': {'status': 401},
        }),
      ],
      response: {},
    );

Request _req() => Request(
      operation: Operation(document: parseString('query Q { x }')),
    );

void main() {
  group('SuwayomiAuthLink session changes', () {
    late bool current;
    late int refreshCalls;
    late int reauthCalls;

    SuwayomiAuthLink guarded({
      Future<Map<String, String>?> Function()? headers,
      Future<RefreshOutcome> Function()? refresh,
    }) => SuwayomiAuthLink(
      authType: () => AuthType.uiLogin,
      getHeaders: headers ?? () async => {'Authorization': 'Bearer OLD'},
      refreshAccessToken: () {
        refreshCalls++;
        return refresh?.call() ?? Future.value(const RefreshSuccess('FRESH'));
      },
      onNeedsReauth: () => reauthCalls++,
      isCurrentSession: () => current,
    );

    final sessionError = isA<StateError>().having(
      (error) => error.message,
      'message',
      'Authentication session changed',
    );

    setUp(() {
      current = true;
      refreshCalls = 0;
      reauthCalls = 0;
    });

    test('rejects an old client before reading credentials', () async {
      var headerCalls = 0;
      final recorder = _RecorderLink([(_) => _ok()]);
      final link = guarded(
        headers: () async {
          headerCalls++;
          return null;
        },
      );
      current = false;

      await expectLater(
        link.concat(recorder).request(_req()),
        emitsError(sessionError),
      );
      expect(headerCalls, 0);
      expect(recorder.callCount, 0);
    });

    test('does not dispatch credentials obtained after a switch', () async {
      final started = Completer<void>();
      final headers = Completer<Map<String, String>?>();
      final recorder = _RecorderLink([(_) => _ok()]);
      final link = guarded(
        headers: () {
          started.complete();
          return headers.future;
        },
      );
      final result = expectLater(
        link.concat(recorder).request(_req()),
        emitsError(sessionError),
      );
      await started.future;
      current = false;
      headers.complete({'Authorization': 'Bearer NEW_ACCOUNT'});

      await result;
      expect(recorder.callCount, 0);
    });

    for (final unauthorized in [false, true]) {
      test(
        'rejects late ${unauthorized ? 'unauthorized' : 'successful'} response',
        () async {
          final started = Completer<void>();
          final response = Completer<Response>();
          final result = expectLater(
            guarded().request(_req(), (_) async* {
              started.complete();
              yield await response.future;
            }),
            emitsError(sessionError),
          );
          await started.future;
          current = false;
          response.complete(unauthorized ? _unauthorized() : _ok());

          await result;
          expect(refreshCalls, 0);
          expect(reauthCalls, 0);
        },
      );
    }

    for (final stage in ['headers', 'response', 'retry']) {
      test('rejects a late HTTP auth error during $stage', () async {
        final started = Completer<void>();
        final failure = Completer<void>();
        var calls = 0;
        final link = guarded(
          headers: stage == 'headers'
              ? () async {
                  started.complete();
                  await failure.future;
                  return null;
                }
              : null,
        );
        final result = expectLater(
          link.request(_req(), (_) async* {
            calls++;
            if (stage == 'retry' && calls == 1) {
              yield _unauthorized();
              return;
            }
            started.complete();
            await failure.future;
            yield _ok();
          }),
          emitsError(sessionError),
        );
        await started.future;
        current = false;
        failure.completeError(
          HttpLinkServerException(
            response: http.Response('Unauthorized', 401),
            parsedResponse: _unauthorized(),
          ),
        );

        await result;
        expect(calls, stage == 'headers' ? 0 : (stage == 'retry' ? 2 : 1));
        expect(refreshCalls, stage == 'retry' ? 1 : 0);
        expect(reauthCalls, 0);
      });
    }

    for (final outcome in <RefreshOutcome>[
      const RefreshSuccess('NEW_ACCOUNT'),
      const RefreshAuthFailure(),
      RefreshTransientFailure(StateError('offline')),
    ]) {
      test('rejects ${outcome.runtimeType} completed after a switch', () async {
        final started = Completer<void>();
        final refresh = Completer<RefreshOutcome>();
        final recorder = _RecorderLink([(_) => _unauthorized(), (_) => _ok()]);
        final link = guarded(
          refresh: () {
            started.complete();
            return refresh.future;
          },
        );
        final result = expectLater(
          link.concat(recorder).request(_req()),
          emitsError(sessionError),
        );
        await started.future;
        current = false;
        refresh.complete(outcome);

        await result;
        expect(recorder.callCount, 1);
        expect(reauthCalls, 0);
      });
    }

    for (final retry in [false, true]) {
      test(
        'guards every ${retry ? 'retried ' : ''}subscription event',
        () async {
          final events = StreamController<Response>();
          final dispatched = Completer<void>();
          var calls = 0;
          final iterator = StreamIterator(
            guarded().request(_req(), (_) {
              calls++;
              if (retry && calls == 1) {
                return Stream.value(_unauthorized());
              }
              dispatched.complete();
              return events.stream;
            }),
          );
          final first = iterator.moveNext();
          await dispatched.future;
          events.add(_ok());
          expect(await first, isTrue);
          expect(iterator.current.data, {'ok': true});
          final second = iterator.moveNext();
          events.add(Response(data: {'tick': 2}, response: {}));
          expect(await second, isTrue);
          expect(iterator.current.data, {'tick': 2});
          final late = expectLater(iterator.moveNext(), throwsA(sessionError));
          current = false;
          events.add(_unauthorized());

          await late;
          await iterator.cancel();
          await events.close();
          expect(reauthCalls, 0);
          expect(refreshCalls, retry ? 1 : 0);
        },
      );
    }
  });

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
        recorder.received[0].context.entry<HttpLinkHeaders>()?.headers[
            'Authorization'],
        'Bearer STALE',
        reason: 'first request uses the stale token before refresh',
      );
      expect(
        recorder.received[1].context.entry<HttpLinkHeaders>()?.headers[
            'Authorization'],
        'Bearer FRESH',
        reason: 'second request MUST use the freshly-refreshed token',
      );
    });

    test('R2-4: retry also returns 401 → onNeedsReauth + surface 401',
        () async {
      bool reauthCalled = false;
      final recorder = _RecorderLink([
        (_) => _unauthorized(), // first call
        (_) => _unauthorized(), // retry with FRESH token also 401
      ]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.uiLogin,
        getHeaders: () async => {'Authorization': 'Bearer STALE'},
        refreshAccessToken: () async => const RefreshSuccess('FRESH'),
        onNeedsReauth: () {
          reauthCalled = true;
        },
      );

      Response? lastResponse;
      await for (final r in link.concat(recorder).request(_req())) {
        lastResponse = r;
      }

      expect(reauthCalled, isTrue,
          reason: 'second 401 after a fresh token must trigger reauth');
      expect(recorder.callCount, 2);
      expect(lastResponse?.errors?.first.message, 'Unauthorized');
    });

    test('transientFailure surfaces original 401 without setting reauth',
        () async {
      bool reauthCalled = false;
      final recorder = _RecorderLink([(_) => _unauthorized()]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.uiLogin,
        getHeaders: () async => {'Authorization': 'Bearer STALE'},
        refreshAccessToken: () async =>
            RefreshOutcome.transientFailure(Exception('network down')),
        onNeedsReauth: () {
          reauthCalled = true;
        },
      );

      Response? lastResponse;
      await for (final r in link.concat(recorder).request(_req())) {
        lastResponse = r;
      }

      expect(reauthCalled, isFalse,
          reason: 'transient (network) refresh failure must NOT mark '
              'the session dead — the refresh token may still be good');
      expect(lastResponse?.errors?.first.message, 'Unauthorized');
    });

    test('does NOT truncate multi-event streams (subscriptions): all '
        'downstream events flow through', () async {
      final downstream = _MultiEventLink([
        Response(data: {'tick': 1}, response: {}),
        Response(data: {'tick': 2}, response: {}),
        Response(data: {'tick': 3}, response: {}),
      ]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.uiLogin,
        getHeaders: () async => {'Authorization': 'Bearer TOK'},
        refreshAccessToken: () async => const RefreshAuthFailure(),
        onNeedsReauth: () {},
      );

      final results = <Response>[];
      await for (final r in link.concat(downstream).request(_req())) {
        results.add(r);
      }
      expect(results.length, 3,
          reason: 'subscription stream truncated — likely '
              'await stream.first regression');
      expect(results.map((r) => r.data?['tick']).toList(), [1, 2, 3]);
    });

    test('on 401 with auth-failure refresh, calls onNeedsReauth and '
        'returns the 401', () async {
      bool reauthCalled = false;
      final recorder = _RecorderLink([(_) => _unauthorized()]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.uiLogin,
        getHeaders: () async => {'Authorization': 'Bearer STALE'},
        refreshAccessToken: () async => const RefreshAuthFailure(),
        onNeedsReauth: () {
          reauthCalled = true;
        },
      );

      Response? lastResponse;
      await for (final r in link.concat(recorder).request(_req())) {
        lastResponse = r;
      }

      expect(reauthCalled, isTrue);
      expect(lastResponse?.errors?.first.message, 'Unauthorized');
    });

    // Note: process-wide single-flight is now an AuthCoordinator concern,
    // not the Link's (R2-3). See AuthCoordinator tests for the dedup
    // assertion; the Link itself just calls `refreshAccessToken` once per
    // 401 it sees, and trusts the coordinator to handle concurrency.
    test('R2-3: Link delegates refresh; one 401 → exactly one refresh call',
        () async {
      int refreshCalls = 0;
      final recorder = _RecorderLink([(_) => _unauthorized(), (_) => _ok()]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.uiLogin,
        getHeaders: () async => {'Authorization': 'Bearer STALE'},
        refreshAccessToken: () async {
          refreshCalls++;
          return const RefreshSuccess('FRESH');
        },
        onNeedsReauth: () {},
      );

      await for (final _ in link.concat(recorder).request(_req())) {}

      expect(refreshCalls, 1,
          reason: 'Link should invoke refreshAccessToken exactly once '
              'per 401 — coordinator dedup is its own concern');
    });
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

    test('on 401, calls onNeedsReauth (no refresh path)', () async {
      bool reauthCalled = false;
      final recorder = _RecorderLink([(_) => _unauthorized()]);
      final link = SuwayomiAuthLink(
        authType: () => AuthType.simpleLogin,
        getHeaders: () async => {'Cookie': 'JSESSIONID=stale'},
        refreshAccessToken: () async => const RefreshAuthFailure(),
        onNeedsReauth: () {
          reauthCalled = true;
        },
      );

      await for (final _ in link.concat(recorder).request(_req())) {}

      expect(reauthCalled, isTrue);
    });
  });
}
