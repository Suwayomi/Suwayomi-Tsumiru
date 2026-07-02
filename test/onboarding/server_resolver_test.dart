// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Unit tests for the "Find server" connection resolver.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tsumiru/src/features/onboarding/data/server_resolver.dart';

// ---------------------------------------------------------------------------
// Canned GraphQL bodies
// ---------------------------------------------------------------------------

const _aboutOk =
    '{"data":{"aboutServer":{"name":"Suwayomi-Server","version":"1.0.0"}}}';
const _authOpen = '{"data":{"downloadStatus":{"__typename":"DownloadStatus"}}}';
const _authUnauthorized =
    '{"data":null,"errors":[{"message":"Unauthorized"}]}';

/// The null-bubbling case the recon warned about: a COMBINED query would null
/// the entire `data` object because the non-null @RequireAuth field's error
/// propagates to the root. We must still read aboutServer from a SEPARATE
/// request — but if someone *did* combine, `data` is null and we must NOT
/// crash; the about-only request is what confirms.
const _nullBubbledCombined =
    '{"data":null,"errors":[{"message":"Unauthorized"}]}';

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

    test('malformed host:port (non-numeric port) never throws', () {
      expect(() => connectionCandidates('host:abc'), returnsNormally);
      expect(connectionCandidates('host:abc'), isEmpty);
    });

    test('userinfo (user@host) never throws', () {
      expect(() => connectionCandidates('user@host:4567'), returnsNormally);
    });

    test('out-of-range port is rejected (fail-fast, no candidates)', () {
      expect(connectionCandidates('host:99999'), isEmpty);
    });

    test('explicit scheme WITH port → single candidate (fully specified)', () {
      expect(connectionCandidates('http://10.0.0.5:4567'),
          ['http://10.0.0.5:4567']);
    });

    test('explicit http scheme, NO port → still tries the default :4567', () {
      // A scheme without a port is NOT a complete address — the user named a
      // host, so we must still try Suwayomi's default port, then bare :80.
      expect(connectionCandidates('http://192.168.0.10'), [
        'http://192.168.0.10:4567',
        'http://192.168.0.10',
      ]);
    });

    test('explicit https scheme, NO port → default :4567 first, then bare', () {
      expect(connectionCandidates('https://suwayomi.example.com'), [
        'https://suwayomi.example.com:4567',
        'https://suwayomi.example.com',
      ]);
    });

    test('bracketed IPv6 with port: two scheme variants on that port', () {
      expect(connectionCandidates('[fe80::1]:4568'), [
        'http://[fe80::1]:4568',
        'https://[fe80::1]:4568',
      ]);
    });

    test('bare IPv6 literal is NOT mistaken for host:port', () {
      // `::1` must keep its colons as the address, not split `:1` as a port.
      final candidates = connectionCandidates('::1');
      expect(candidates, [
        'http://[::1]:4567',
        'https://[::1]',
        'http://[::1]',
      ]);
    });

    test('longer bare IPv6 literal (fe80::1) is detected', () {
      final candidates = connectionCandidates('fe80::1');
      expect(candidates.first, 'http://[fe80::1]:4567');
      expect(candidates, contains('http://[fe80::1]'));
    });

    test('base path is preserved (explicit port → two variants)', () {
      expect(connectionCandidates('host.example:8080/suwayomi'), [
        'http://host.example:8080/suwayomi',
        'https://host.example:8080/suwayomi',
      ]);
    });

    test('trailing slash is normalised away (no duplicates)', () {
      // bare host with trailing slash should equal bare host.
      expect(connectionCandidates('myhost/'), connectionCandidates('myhost'));
    });

    test('explicit scheme + port + base path → single candidate, path kept', () {
      expect(connectionCandidates('https://host.example:8080/suwayomi/'),
          ['https://host.example:8080/suwayomi']);
    });

    test('blank input yields no candidates', () {
      expect(connectionCandidates('   '), isEmpty);
    });

    test('explicit scheme-default port (:80) reads as no port → fans to :4567',
        () {
      // Dart's Uri treats a scheme-default port as "no port", so http://host:80
      // is indistinguishable from http://host — we fan out to the default :4567
      // first (a server is rarely on :80), then bare.
      expect(connectionCandidates('http://host.example:80'),
          ['http://host.example:4567', 'http://host.example']);
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

    test('reads aboutServer name/version INDEPENDENTLY of errors[]', () {
      // Partial data: aboutServer present AND an errors array present.
      const partial =
          '{"data":{"aboutServer":{"name":"S","version":"9"}},"errors":[{"message":"something else"}]}';
      final r = classifyProbeBody(
        url: 'http://h',
        aboutBody: partial,
        authBody: _authUnauthorized,
      );
      expect(r!.confirmed, isTrue);
      expect(r.serverName, 'S');
      expect(r.serverVersion, '9');
    });

    test('null-bubbled combined response does NOT confirm (no aboutServer)',
        () {
      // If the about request itself came back null-bubbled, there's no
      // aboutServer object → not confirmed.
      final r = classifyProbeBody(
        url: 'http://h',
        aboutBody: _nullBubbledCombined,
        authBody: _authUnauthorized,
      );
      expect(r, isNull);
    });

    test('case-insensitive "unauthor" substring trips authRequired', () {
      const weird = '{"errors":[{"message":"UNAUTHORISED access denied"}]}';
      final r = classifyProbeBody(
        url: 'http://h',
        aboutBody: _aboutOk,
        authBody: weird,
      );
      expect(r!.authMode, ProbeAuthMode.authRequired);
    });

    test('non-JSON / html body is not confirmed', () {
      final r = classifyProbeBody(
        url: 'http://h',
        aboutBody: '<html>login</html>',
        authBody: '',
      );
      expect(r, isNull);
    });
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

    test('basic-gated is the best fallback when nothing confirms', () async {
      final r = await resolveServer(
        'gated.example',
        client: MockClient((_) async => http.Response('', 401)),
        probe: (url) async => ProbeResult.basicGatedResult(url),
      );
      expect(r.outcome, ResolveOutcome.basicGated);
      expect(r.isFound, isFalse); // basic-gated NEVER reads as found
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

    test('all not-reached → notReached on the first candidate', () async {
      final r = await resolveServer(
        'dead.example',
        client: MockClient((_) async => http.Response('', 200)),
        probe: (url) async => ProbeResult.notReached(url),
      );
      expect(r.outcome, ResolveOutcome.notReached);
      expect(r.baseUrl, 'http://dead.example:4567');
    });

    test('unparseable input falls back to a scheme-bearing URL', () async {
      final r = await resolveServer(
        'host:abc', // malformed → no candidates
        client: MockClient((_) async => http.Response('', 200)),
      );
      expect(r.outcome, ResolveOutcome.notReached);
      expect(r.baseUrl, startsWith('http://')); // never raw schemeless text
    });
  });

  group('displayAddress — always shows the explicit host:port', () {
    test('non-default port is kept', () {
      expect(displayAddress('http://192.168.0.10:4567'),
          'http://192.168.0.10:4567');
    });
    test('http default :80 is made explicit (not hidden)', () {
      expect(displayAddress('http://192.168.0.10'), 'http://192.168.0.10:80');
    });
    test('https default :443 is made explicit', () {
      expect(displayAddress('https://suwayomi.example.com'),
          'https://suwayomi.example.com:443');
    });
    test('base path is preserved after the port', () {
      expect(displayAddress('http://host.example/suwayomi'),
          'http://host.example:80/suwayomi');
    });
    test('IPv6 host is bracketed', () {
      expect(displayAddress('http://[::1]:4567'), 'http://[::1]:4567');
    });
  });

  group('normalisedFallbackUrl — use-this-address-anyway always has a scheme',
      () {
    test('bare host gets http:// + default port', () {
      expect(normalisedFallbackUrl('192.168.0.10'), startsWith('http://'));
    });
    test('explicit scheme is preserved', () {
      expect(normalisedFallbackUrl('https://x.example'), 'https://x.example');
    });
    test('malformed input still gets a scheme', () {
      expect(normalisedFallbackUrl('weird input'), startsWith('http://'));
    });
  });

  group('probeServer — wire behaviour via MockClient', () {
    test('confirms a Suwayomi server and reads auth mode', () async {
      final mock = MockClient.streaming((request, bodyStream) async {
        final body = await bodyStream.bytesToString();
        final query = (jsonDecode(body) as Map)['query'] as String;
        expect(request.url.path, '/api/graphql');
        if (query.contains('aboutServer')) {
          return http.StreamedResponse(
              Stream.value(utf8.encode(_aboutOk)), 200);
        }
        // auth probe → unauthorized
        return http.StreamedResponse(
            Stream.value(utf8.encode(_authUnauthorized)), 200);
      });
      final r = await probeServer('http://h:4567', client: mock);
      expect(r.confirmed, isTrue);
      expect(r.authMode, ProbeAuthMode.authRequired);
    });

    test('401 + WWW-Authenticate: Basic → basicGated', () async {
      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('')),
          401,
          headers: {'www-authenticate': 'Basic realm="suwayomi"'},
        );
      });
      final r = await probeServer('http://h:4567', client: mock);
      expect(r.basicGated, isTrue);
      expect(r.confirmed, isFalse);
    });

    test('https→http downgrade redirect is NOT followed → reachedUnconfirmed',
        () async {
      final mock = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('')),
          302,
          headers: {'location': 'http://h:4567/login'},
        );
      });
      final r = await probeServer('https://h:4567', client: mock);
      expect(r.reached, isTrue);
      expect(r.confirmed, isFalse);
      expect(r.basicGated, isFalse);
    });

    test('single-hop redirect to a confirmable endpoint → found at destination',
        () async {
      final mock = MockClient.streaming((request, bodyStream) async {
        if (request.url.host == 'proxy.example') {
          // The proxy bounces /api/graphql to the real origin (same scheme).
          return http.StreamedResponse(Stream.value(utf8.encode('')), 302,
              headers: {'location': 'https://real.example/api/graphql'});
        }
        final body = await bodyStream.bytesToString();
        final isAbout =
            ((jsonDecode(body) as Map)['query'] as String).contains('aboutServer');
        return http.StreamedResponse(
            Stream.value(utf8.encode(isAbout ? _aboutOk : _authOpen)), 200);
      });
      final r = await probeServer('https://proxy.example', client: mock);
      expect(r.confirmed, isTrue);
      expect(r.url, 'https://real.example'); // persists the DESTINATION base
    });

    test('a second redirect is not chased → reachedUnconfirmed', () async {
      final mock = MockClient.streaming((request, bodyStream) async {
        // Every request redirects again (same scheme, no downgrade).
        return http.StreamedResponse(Stream.value(utf8.encode('')), 302, headers: {
          'location': 'https://${request.url.host}x/api/graphql',
        });
      });
      final r = await probeServer('https://loop.example', client: mock);
      expect(r.confirmed, isFalse);
      expect(r.reached, isTrue);
    });

    test('auth probe unreadable (request throws) → assume authRequired',
        () async {
      // The doc contract: "assume auth-required if B is unreadable". An open
      // read here onboards an auth server with no login step → Unauthorized
      // on first real query.
      var calls = 0;
      final mock = MockClient.streaming((request, bodyStream) async {
        calls++;
        if (calls == 1) {
          return http.StreamedResponse(
              Stream.value(utf8.encode(_aboutOk)), 200);
        }
        throw http.ClientException('boom');
      });
      final r = await probeServer('http://h:4567', client: mock);
      expect(r.confirmed, isTrue);
      expect(r.authMode, ProbeAuthMode.authRequired);
    });
  });

  group('webAuthRequired — the web Test-connection auth probe', () {
    test('unauthorized errors body → true', () async {
      final mock = MockClient((_) async =>
          http.Response(_authUnauthorized, 200));
      expect(
          await webAuthRequired('http://h:4568', client: mock), isTrue);
    });

    test('open data body → false', () async {
      final mock = MockClient((_) async => http.Response(_authOpen, 200));
      expect(
          await webAuthRequired('http://h:4568', client: mock), isFalse);
    });

    test('401 status → true', () async {
      final mock = MockClient((_) async => http.Response('', 401));
      expect(
          await webAuthRequired('http://h:4568', client: mock), isTrue);
    });

    test('transport failure → true (safe default; about already confirmed)',
        () async {
      final mock = MockClient((_) async =>
          throw http.ClientException('network'));
      expect(
          await webAuthRequired('http://h:4568', client: mock), isTrue);
    });

    test('posts the @RequireAuth probe to /api/graphql with redirects ON',
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
    });
  });

  group('shouldSuggestHttps — reverse-proxy hint only when https not tried', () {
    test('explicit http:// → https was never tried → suggest https', () {
      expect(shouldSuggestHttps('http://192.168.0.10:4567'), isTrue);
    });
    test('bare host → https IS a candidate → do NOT suggest', () {
      expect(shouldSuggestHttps('192.168.0.10'), isFalse);
    });
    test('explicit https:// → already https → do NOT suggest', () {
      expect(shouldSuggestHttps('https://suwayomi.example.com'), isFalse);
    });
  });

  group('basicAuthConfirms — verifies Basic creds against aboutServer', () {
    test('valid Basic creds → aboutServer confirms → true', () async {
      final mock = MockClient.streaming((request, _) async {
        final auth = request.headers['authorization'] ?? '';
        if (auth.startsWith('Basic ')) {
          return http.StreamedResponse(
              Stream.value(utf8.encode(_aboutOk)), 200);
        }
        return http.StreamedResponse(Stream.value(utf8.encode('')), 401,
            headers: {'www-authenticate': 'Basic'});
      });
      expect(
          await basicAuthConfirms('http://h:4567',
              client: mock, username: 'u', password: 'p'),
          isTrue);
    });

    test('wrong Basic creds → 401 → false', () async {
      final mock = MockClient.streaming((_, __) async => http.StreamedResponse(
          Stream.value(utf8.encode('')), 401,
          headers: {'www-authenticate': 'Basic'}));
      expect(
          await basicAuthConfirms('http://h:4567',
              client: mock, username: 'u', password: 'x'),
          isFalse);
    });

    test('reached but not Suwayomi (200 non-JSON) → false', () async {
      final mock = MockClient.streaming((_, __) async =>
          http.StreamedResponse(Stream.value(utf8.encode('<html>')), 200));
      expect(
          await basicAuthConfirms('http://h:4567',
              client: mock, username: 'u', password: 'p'),
          isFalse);
    });
  });

  group('authProbeAuthorized — verifies a credential against @RequireAuth', () {
    test('a credential the @RequireAuth gate rejects → not authorised',
        () async {
      // Server honours ONLY the bearer (models ui_login): a cookie gets
      // Unauthorized, a bearer gets data.
      final mock = MockClient.streaming((request, _) async {
        final hasBearer =
            request.headers['authorization']?.startsWith('Bearer ') ?? false;
        return http.StreamedResponse(
            Stream.value(utf8.encode(hasBearer ? _authOpen : _authUnauthorized)),
            200);
      });
      expect(
          await authProbeAuthorized('http://h:4567',
              client: mock, cookie: 'JSESSIONID=abc'),
          isFalse);
      expect(
          await authProbeAuthorized('http://h:4567',
              client: mock, bearer: 'jwt.token'),
          isTrue);
    });

    test('a 401 status reads as not authorised', () async {
      final mock = MockClient.streaming((_, __) async =>
          http.StreamedResponse(Stream.value(utf8.encode('')), 401));
      expect(
          await authProbeAuthorized('http://h:4567',
              client: mock, cookie: 'x'),
          isFalse);
    });

    test('basic credential the @RequireAuth gate authorises → true', () async {
      // Models genuine basic_auth: the gate returns data ONLY when a Basic
      // Authorization header is present.
      final mock = MockClient.streaming((request, _) async {
        final hasBasic =
            request.headers['authorization']?.startsWith('Basic ') ?? false;
        return http.StreamedResponse(
            Stream.value(utf8.encode(hasBasic ? _authOpen : _authUnauthorized)),
            200);
      });
      expect(
          await authProbeAuthorized('http://h:4567',
              client: mock, basic: 'u:p'),
          isTrue);
    });

    test('basic credential on a server that ignores it → not authorised',
        () async {
      // Models picking "Basic" on a ui_login/simple_login server: the public
      // surface answers, but the @RequireAuth probe stays Unauthorized because
      // a Basic header is meaningless to that server. THIS is the bug guard —
      // a wrong auth type must NOT read as authorised.
      final mock = MockClient.streaming((_, __) async => http.StreamedResponse(
          Stream.value(utf8.encode(_authUnauthorized)), 200));
      expect(
          await authProbeAuthorized('http://h:4567',
              client: mock, basic: 'u:wrong'),
          isFalse);
    });
  });

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
            200);
      });
      final mode = await verifyAuthMode(
        baseUrl: 'http://h:4567',
        client: mock,
        obtainSimpleCookie: () async => 'JSESSIONID=abc', // login "succeeded"
        obtainUiBearer: () async => 'jwt.token',
      );
      expect(mode, VerifiedAuthMode.uiLogin);
    });

    test('simple_login server: cookie authorises → simpleLogin, ui not tried',
        () async {
      var uiTried = false;
      final mock = MockClient.streaming((request, _) async {
        final hasCookie =
            (request.headers['cookie']?.isNotEmpty) ?? false;
        return http.StreamedResponse(
            Stream.value(utf8.encode(hasCookie ? _authOpen : _authUnauthorized)),
            200);
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
      expect(uiTried, isFalse,
          reason: 'simple verified first → ui-login never attempted');
    });

    test('wrong credentials (neither authorises) → null', () async {
      final mock = MockClient.streaming((_, __) async =>
          http.StreamedResponse(
              Stream.value(utf8.encode(_authUnauthorized)), 200));
      final mode = await verifyAuthMode(
        baseUrl: 'http://h:4567',
        client: mock,
        obtainSimpleCookie: () async => 'JSESSIONID=abc',
        obtainUiBearer: () async => 'jwt',
      );
      expect(mode, isNull);
    });

    test('simple-login throwing (bad simple creds) falls through to ui',
        () async {
      final mock = MockClient.streaming((request, _) async {
        final hasBearer =
            request.headers['authorization']?.startsWith('Bearer ') ?? false;
        return http.StreamedResponse(
            Stream.value(utf8.encode(hasBearer ? _authOpen : _authUnauthorized)),
            200);
      });
      final mode = await verifyAuthMode(
        baseUrl: 'http://h:4567',
        client: mock,
        obtainSimpleCookie: () async => throw Exception('bad simple creds'),
        obtainUiBearer: () async => 'jwt',
      );
      expect(mode, VerifiedAuthMode.uiLogin);
    });
  });
}
