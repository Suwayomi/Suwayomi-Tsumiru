import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tsumiru/src/features/auth/data/auth_coordinator.dart';
import 'package:tsumiru/src/features/offline/data/background/background_token_record.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';

String _jwt(DateTime exp) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

void main() {
  final now = DateTime.utc(2026, 9, 24, 18, 20);

  group('describeRefreshOutcome', () {
    test('reports the new token lifetime, never the token', () {
      final token = _jwt(now.add(const Duration(minutes: 5)));
      final line = describeRefreshOutcome(RefreshSuccess(token), now: now);
      expect(line, 'outcome=success expIn=300s');
      expect(line, isNot(contains(token)));
    });

    test('names the transient cause by type and first line only', () {
      final line = describeRefreshOutcome(
        RefreshTransientFailure(StateError('credentials store not hydrated\nx')),
      );
      expect(
        line,
        'outcome=transient cause=StateError: '
        'Bad state: credentials store not hydrated',
      );
    });

    test('covers not-due and auth failure', () {
      expect(describeRefreshOutcome(null), 'outcome=not-due');
      expect(
        describeRefreshOutcome(const RefreshAuthFailure()),
        'outcome=auth-failure',
      );
    });

    test('token expiry handles missing and undecodable tokens', () {
      expect(describeTokenExpiry(null), 'token=none');
      expect(describeTokenExpiry('not-a-jwt'), 'exp=unknown');
      expect(
        describeTokenExpiry(
          _jwt(now.subtract(const Duration(minutes: 2))),
          now: now,
        ),
        'expIn=-120s',
      );
    });
  });

  group('background refresh diagnostics', () {
    final lines = <String>[];
    setUp(() {
      lines.clear();
      setDiagnosticSink(lines.add);
    });
    tearDown(() => setDiagnosticSink(null));

    test('keeps the wrapped socket error type visible', () {
      logBackgroundRefresh(
        'notify',
        'error transient=false',
        http.ClientException(
          'SocketException: Failed host lookup',
          Uri.parse('https://server/api/graphql'),
        ),
      );
      expect(lines.single, contains('offline-refresh: source=notify'));
      expect(lines.single, contains('cause=ClientException: '));
    });

    test('broker logs why a 401 ended without a refresh', () async {
      const record = BackgroundTokenRecord(
        gen: 3,
        authType: 'uiLogin',
        accessToken: 'SAME',
      );
      final broker = TokenBroker(
        read: () async => record,
        write: (_) async {},
        refreshFn: (_) async => (tokens: null, transient: false),
      );
      expect(await broker.resolveAfter401('SAME'), isNull);
      expect(lines, [
        contains('token-broker: auth-rejected gen=3'),
        contains('token-broker: no-refresh-token gen=3'),
      ]);
    });

    test('broker logs an identity change during the refresh', () async {
      const owner = BackgroundTokenRecord(
        gen: 1,
        authType: 'uiLogin',
        accessToken: 'A',
        refreshToken: 'R',
        identityEpoch: 1,
        catalogServerId: 'a',
        originalRefreshToken: 'R',
      );
      var current = owner;
      final broker = TokenBroker(
        expectedIdentity: owner,
        read: () async => current,
        write: (_) async {},
        refreshFn: (_) async {
          current = const BackgroundTokenRecord(
            gen: 2,
            authType: 'uiLogin',
            accessToken: 'B',
            refreshToken: 'R2',
            identityEpoch: 2,
            catalogServerId: 'b',
            originalRefreshToken: 'R2',
          );
          return (tokens: (access: 'C', refresh: 'R'), transient: false);
        },
      );
      expect(await broker.resolveAfter401('A'), isNull);
      expect(lines, [
        contains('token-broker: auth-rejected gen=1'),
        contains('token-broker: identity-changed-during-refresh'),
      ]);
      expect(lines.join(), isNot(contains('R2')));
    });

    test('broker logs a successful refresh with the new generation', () async {
      var current = const BackgroundTokenRecord(
        gen: 4,
        authType: 'uiLogin',
        accessToken: 'A',
        refreshToken: 'R',
      );
      final broker = TokenBroker(
        read: () async => current,
        write: (r) async => current = r,
        refreshFn: (_) async =>
            (tokens: (access: 'B', refresh: 'R2'), transient: false),
      );
      expect(await broker.resolveAfter401('A'), 'B');
      expect(lines, [
        contains('token-broker: auth-rejected gen=4'),
        contains('token-broker: refreshed gen=5'),
      ]);
      expect(lines.join(), isNot(contains('R2')));
    });

    test('a refresh ahead of expiry is not logged as a rejection', () async {
      String part(Object json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final expired =
          '${part({'alg': 'HS256'})}.'
          '${part({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60})}'
          '.sig';
      var current = BackgroundTokenRecord(
        gen: 2,
        authType: 'uiLogin',
        accessToken: expired,
        refreshToken: 'R',
      );
      final broker = TokenBroker(
        read: () async => current,
        write: (r) async => current = r,
        refreshFn: (_) async =>
            (tokens: (access: 'B', refresh: 'R'), transient: false),
      );
      await broker.refreshIfDue(current);
      expect(lines, [
        contains('token-broker: refreshed gen=3'),
        matches(RegExp(r'token-broker: refresh-ahead expIn=-\d+s ok')),
      ]);
    });
  });

  test('SocketException stays distinct from the ClientException wrapper', () {
    // Documents why the background refreshFns log the caught type: a bare
    // `on SocketException` does not match what package:http throws.
    final wrapped = http.ClientException('SocketException: x');
    expect(wrapped, isNot(isA<SocketException>()));
  });
}
