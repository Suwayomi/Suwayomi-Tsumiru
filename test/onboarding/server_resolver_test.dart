// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Unit tests for the "Find server" connection resolver.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/onboarding/data/server_resolver.dart';

// ---------------------------------------------------------------------------
// Canned GraphQL bodies
// ---------------------------------------------------------------------------

const _aboutOk =
    '{"data":{"aboutServer":{"name":"Suwayomi-Server","version":"1.0.0"}}}';
const _authOpen = '{"data":{"downloadStatus":{"__typename":"DownloadStatus"}}}';
const _authUnauthorized = '{"data":null,"errors":[{"message":"Unauthorized"}]}';

/// The documented shape of each auth mode, driven over the wire: both
/// GraphQL probes answer, and GET / gives the root hop detection reads.
http.Client _authModeClient({required int rootStatus, String? rootLocation}) =>
    MockClient.streaming((request, bodyStream) async {
      if (request.method == 'GET') {
        final headers = <String, String>{};
        if (rootLocation != null) headers['location'] = rootLocation;
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          rootStatus,
          headers: headers,
        );
      }
      final query =
          (jsonDecode(await bodyStream.bytesToString()) as Map)['query']
              as String;
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            query.contains('aboutServer') ? _aboutOk : _authUnauthorized,
          ),
        ),
        200,
      );
    });

void main() {
  test('connection candidates are ordered and normalised', () {
    expect(connectionCandidates('192.168.0.10'), [
      'http://192.168.0.10:4567',
      'https://192.168.0.10',
      'http://192.168.0.10',
    ]);
    expect(connectionCandidates('myserver.local:4568'), [
      'http://myserver.local:4568',
      'https://myserver.local:4568',
    ]);
  });

  test('probe classification and detected auth type table', () async {
    final open = classifyProbeBody(
      url: 'http://h:4567',
      aboutBody: _aboutOk,
      authBody: _authOpen,
    );
    expect(open, isNotNull);
    expect(open!.confirmed, isTrue);
    expect(open.authMode, ProbeAuthMode.open);
    expect(open.serverName, 'Suwayomi-Server');
    expect(open.serverVersion, '1.0.0');

    final gated = classifyProbeBody(
      url: 'http://h:4567',
      aboutBody: _aboutOk,
      authBody: _authUnauthorized,
    );
    expect(gated!.confirmed, isTrue);
    expect(gated.authMode, ProbeAuthMode.authRequired);

    // basic_auth: 401 + Basic challenge → AuthType.basic.
    final basicClient = MockClient.streaming(
      (_, _) async => http.StreamedResponse(
        const Stream<List<int>>.empty(),
        401,
        headers: {'www-authenticate': 'Basic realm="suwayomi"'},
      ),
    );
    final basic = await resolveServer('http://h:4567', client: basicClient);
    expect(basic.outcome, ResolveOutcome.basicGated);
    expect(basic.detectedAuthType, AuthType.basic);

    // simple_login: Unauthorized probe + root 303 to /login.html.
    final simple = await resolveServer(
      'http://h:4567',
      client: _authModeClient(rootStatus: 303, rootLocation: '/login.html'),
    );
    expect(simple.outcome, ResolveOutcome.found);
    expect(simple.authMode, ProbeAuthMode.authRequired);
    expect(simple.detectedAuthType, AuthType.simpleLogin);

    // ui_login: Unauthorized probe + root 200.
    final ui = await resolveServer(
      'http://h:4567',
      client: _authModeClient(rootStatus: 200),
    );
    expect(ui.outcome, ResolveOutcome.found);
    expect(ui.authMode, ProbeAuthMode.authRequired);
    expect(ui.detectedAuthType, AuthType.uiLogin);
  });

  test('ladder walk', () async {
    final tried = <String>[];
    final first = await resolveServer(
      '192.168.0.10',
      client: MockClient((_) async => http.Response('', 200)),
      probe: (url) async {
        tried.add(url);
        return ProbeResult(
          url: url,
          confirmed: true,
          reached: true,
          basicGated: false,
          authMode: ProbeAuthMode.open,
          serverName: 'Suwayomi-Server',
          serverVersion: '1.0.0',
        );
      },
    );
    expect(first.isFound, isTrue);
    expect(first.baseUrl, 'http://192.168.0.10:4567');
    expect(tried, ['http://192.168.0.10:4567']); // stopped at first

    // A basic-gated first candidate never wins over a later confirmed one.
    final later = await resolveServer(
      'myserver',
      client: MockClient((_) async => http.Response('', 200)),
      probe: (url) async {
        if (url.startsWith('http://')) {
          return ProbeResult.basicGatedResult(url);
        }
        return ProbeResult(
          url: url,
          confirmed: true,
          reached: true,
          basicGated: false,
          authMode: ProbeAuthMode.open,
          serverName: 'S',
          serverVersion: '1',
        );
      },
    );
    expect(later.isFound, isTrue);
    expect(later.outcome, ResolveOutcome.found);
    expect(later.baseUrl, startsWith('https://'));

    // Fallback priority: reached-unconfirmed beats not-reached.
    final fallback = await resolveServer(
      'mystery.example',
      client: MockClient((_) async => http.Response('', 200)),
      probe: (url) async {
        if (url == 'http://mystery.example') {
          return ProbeResult.reachedUnconfirmed(url);
        }
        return ProbeResult.notReached(url);
      },
    );
    expect(fallback.outcome, ResolveOutcome.reachedUnconfirmed);
    expect(fallback.baseUrl, 'http://mystery.example');
  });

  test('verified submit-time try-both', () async {
    // The @RequireAuth gate honours only the bearer. /login.html still
    // "succeeds" (we hand back a cookie), but that cookie is INERT at the
    // API — exactly the ui_login-cookie trap. Verifying via re-probe
    // correctly yields uiLogin.
    final bearerOnly = MockClient.streaming((request, _) async {
      final hasBearer =
          request.headers['authorization']?.startsWith('Bearer ') ?? false;
      return http.StreamedResponse(
        Stream.value(utf8.encode(hasBearer ? _authOpen : _authUnauthorized)),
        200,
      );
    });
    expect(
      await verifyAuthMode(
        baseUrl: 'http://h:4567',
        client: bearerOnly,
        obtainSimpleCookie: () async => 'JSESSIONID=abc',
        obtainUiBearer: () async => 'jwt.token',
      ),
      VerifiedAuthMode.uiLogin,
    );

    // A cookie-authorising server verifies as simpleLogin; ui is not tried.
    var uiTried = false;
    final cookieOnly = MockClient.streaming((request, _) async {
      final hasCookie = (request.headers['cookie']?.isNotEmpty) ?? false;
      return http.StreamedResponse(
        Stream.value(utf8.encode(hasCookie ? _authOpen : _authUnauthorized)),
        200,
      );
    });
    expect(
      await verifyAuthMode(
        baseUrl: 'http://h:4567',
        client: cookieOnly,
        obtainSimpleCookie: () async => 'JSESSIONID=abc',
        obtainUiBearer: () async {
          uiTried = true;
          return 'jwt';
        },
      ),
      VerifiedAuthMode.simpleLogin,
    );
    expect(
      uiTried,
      isFalse,
      reason: 'simple verified first → ui-login never attempted',
    );

    // Simple-login throwing (bad simple creds) falls through to ui.
    expect(
      await verifyAuthMode(
        baseUrl: 'http://h:4567',
        client: bearerOnly,
        obtainSimpleCookie: () async => throw Exception('bad simple creds'),
        obtainUiBearer: () async => 'jwt',
      ),
      VerifiedAuthMode.uiLogin,
    );
  });
}
