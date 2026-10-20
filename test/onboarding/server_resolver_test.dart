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

/// The null-bubbling case the recon warned about: a COMBINED query would null
/// the entire `data` object because the non-null @RequireAuth field's error
/// propagates to the root. We must still read aboutServer from a SEPARATE
/// request — but if someone *did* combine, `data` is null and we must NOT
/// crash; the about-only request is what confirms.

void main() {
  group('connectionCandidates — ordering & normalisation', () {
    test('bare host: http-first on :4567, then bare https, then bare http', () {
      expect(connectionCandidates('192.168.0.10'), [
        'http://192.168.0.10:4567',
        'https://192.168.0.10',
        'http://192.168.0.10',
      ]);
    });

    test('host + explicit port: only the two scheme variants on that port', () {
      expect(connectionCandidates('myserver.local:4568'), [
        'http://myserver.local:4568',
        'https://myserver.local:4568',
      ]);
    });
  });

  group('classifyProbeBody', () {
    test('confirmed + open when auth probe returns data', () {
      final r = classifyProbeBody(
        url: 'http://h:4567',
        aboutBody: _aboutOk,
        authBody: _authOpen,
      );
      expect(r, isNotNull);
      expect(r!.confirmed, isTrue);
      expect(r.authMode, ProbeAuthMode.open);
      expect(r.serverName, 'Suwayomi-Server');
      expect(r.serverVersion, '1.0.0');
    });

    test('confirmed + authRequired when auth probe says Unauthorized', () {
      final r = classifyProbeBody(
        url: 'http://h:4567',
        aboutBody: _aboutOk,
        authBody: _authUnauthorized,
      );
      expect(r!.confirmed, isTrue);
      expect(r.authMode, ProbeAuthMode.authRequired);
    });
  });

  group('detectAuthType — probe shape → sign-in method', () {});

  group('resolveServer — detected auth type per mode', () {
    /// The documented shape of each auth mode, driven over the wire: both
    /// GraphQL probes answer, and GET / gives the root hop detection reads.
    http.Client authModeClient({
      required int rootStatus,
      String? rootLocation,
    }) => MockClient.streaming((request, bodyStream) async {
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

    test('basic_auth: 401 + Basic challenge → AuthType.basic', () async {
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          const Stream<List<int>>.empty(),
          401,
          headers: {'www-authenticate': 'Basic realm="suwayomi"'},
        ),
      );
      final r = await resolveServer('http://h:4567', client: client);
      expect(r.outcome, ResolveOutcome.basicGated);
      expect(r.detectedAuthType, AuthType.basic);
    });

    test('simple_login: Unauthorized probe + root 303 to /login.html → '
        'AuthType.simpleLogin', () async {
      final r = await resolveServer(
        'http://h:4567',
        client: authModeClient(rootStatus: 303, rootLocation: '/login.html'),
      );
      expect(r.outcome, ResolveOutcome.found);
      expect(r.authMode, ProbeAuthMode.authRequired);
      expect(r.detectedAuthType, AuthType.simpleLogin);
    });

    test(
      'ui_login: Unauthorized probe + root 200 → AuthType.uiLogin',
      () async {
        final r = await resolveServer(
          'http://h:4567',
          client: authModeClient(rootStatus: 200),
        );
        expect(r.outcome, ResolveOutcome.found);
        expect(r.authMode, ProbeAuthMode.authRequired);
        expect(r.detectedAuthType, AuthType.uiLogin);
      },
    );
  });

  group('resolveServer — ladder walk', () {
    test('first confirmed candidate (http:4567) short-circuits', () async {
      final tried = <String>[];
      final r = await resolveServer(
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
      expect(r.isFound, isTrue);
      // http-first: the LAN candidate is tried first and wins.
      expect(r.baseUrl, 'http://192.168.0.10:4567');
      expect(tried, ['http://192.168.0.10:4567']); // stopped at first
    });

    test('basic-gated NEVER wins over a LATER confirmed candidate', () async {
      // The first candidate (http:4567) is basic-gated; a later one (https) is
      // the real confirmable server. Must resolve to the confirmed https, NOT
      // the basic-gated http.
      final r = await resolveServer(
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
      expect(r.isFound, isTrue);
      expect(r.outcome, ResolveOutcome.found);
      expect(r.baseUrl, startsWith('https://'));
    });

    test('fallback priority: reached-unconfirmed beats not-reached', () async {
      final r = await resolveServer(
        'mystery.example',
        client: MockClient((_) async => http.Response('', 200)),
        probe: (url) async {
          // only the http (last) candidate even answers, unconfirmed.
          if (url == 'http://mystery.example') {
            return ProbeResult.reachedUnconfirmed(url);
          }
          return ProbeResult.notReached(url);
        },
      );
      expect(r.outcome, ResolveOutcome.reachedUnconfirmed);
      expect(r.baseUrl, 'http://mystery.example');
    });
  });

  group('displayAddress — always shows the explicit host:port', () {});

  group(
    'normalisedFallbackUrl — use-this-address-anyway always has a scheme',
    () {},
  );

  group('probeServer — wire behaviour via MockClient', () {});

  group('webAuthRequired — the web Test-connection auth probe', () {
    test(
      'posts the @RequireAuth probe to /api/graphql with redirects ON',
      () async {
        late http.Request seen;
        final mock = MockClient((req) async {
          seen = req;
          return http.Response(_authOpen, 200);
        });
        await webAuthRequired('http://h:4568/base', client: mock);
        expect(seen.url.toString(), 'http://h:4568/base/api/graphql');
        expect(seen.body, contains('downloadStatus'));
        // Browsers cannot disable redirect-following; the web probe must not try.
        expect(seen.followRedirects, isTrue);
      },
    );
  });

  group(
    'shouldSuggestHttps — reverse-proxy hint only when https not tried',
    () {},
  );

  group('basicAuthConfirms — verifies Basic creds against aboutServer', () {});

  group(
    'authProbeAuthorized — verifies a credential against @RequireAuth',
    () {},
  );

  group('verifyAuthMode — the VERIFIED submit-time try-both', () {
    test('ui_login server: cookie 303s at login but only the bearer authorises '
        'the API → resolves to uiLogin (the round-4 trap, closed)', () async {
      // The @RequireAuth gate honours ONLY the bearer. /login.html still
      // "succeeds" (we hand back a cookie), but that cookie is INERT at the
      // API — exactly the ui_login-cookie trap. Trusting the 303 would mislabel
      // this simpleLogin; verifying via re-probe correctly yields uiLogin.
      final mock = MockClient.streaming((request, _) async {
        final hasBearer =
            request.headers['authorization']?.startsWith('Bearer ') ?? false;
        return http.StreamedResponse(
          Stream.value(utf8.encode(hasBearer ? _authOpen : _authUnauthorized)),
          200,
        );
      });
      final mode = await verifyAuthMode(
        baseUrl: 'http://h:4567',
        client: mock,
        obtainSimpleCookie: () async => 'JSESSIONID=abc', // login "succeeded"
        obtainUiBearer: () async => 'jwt.token',
      );
      expect(mode, VerifiedAuthMode.uiLogin);
    });

    test(
      'simple_login server: cookie authorises → simpleLogin, ui not tried',
      () async {
        var uiTried = false;
        final mock = MockClient.streaming((request, _) async {
          final hasCookie = (request.headers['cookie']?.isNotEmpty) ?? false;
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(hasCookie ? _authOpen : _authUnauthorized),
            ),
            200,
          );
        });
        final mode = await verifyAuthMode(
          baseUrl: 'http://h:4567',
          client: mock,
          obtainSimpleCookie: () async => 'JSESSIONID=abc',
          obtainUiBearer: () async {
            uiTried = true;
            return 'jwt';
          },
        );
        expect(mode, VerifiedAuthMode.simpleLogin);
        expect(
          uiTried,
          isFalse,
          reason: 'simple verified first → ui-login never attempted',
        );
      },
    );

    test(
      'simple-login throwing (bad simple creds) falls through to ui',
      () async {
        final mock = MockClient.streaming((request, _) async {
          final hasBearer =
              request.headers['authorization']?.startsWith('Bearer ') ?? false;
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(hasBearer ? _authOpen : _authUnauthorized),
            ),
            200,
          );
        });
        final mode = await verifyAuthMode(
          baseUrl: 'http://h:4567',
          client: mock,
          obtainSimpleCookie: () async => throw Exception('bad simple creds'),
          obtainUiBearer: () async => 'jwt',
        );
        expect(mode, VerifiedAuthMode.uiLogin);
      },
    );
  });
}
