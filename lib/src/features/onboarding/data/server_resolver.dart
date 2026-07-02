// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// "Find server" connection resolver.
///
/// The onboarding Step 2 lets a user type a half-remembered address — a bare
/// host, `host:port`, a full `https://…/suwayomi` URL, an IPv6 literal — and
/// have the app figure out the working base URL (and whether it needs auth)
/// without making them understand schemes/ports. This file is the PURE,
/// testable core of that:
///
///   * [connectionCandidates] turns one fuzzy input into an ordered ladder of
///     concrete base URLs to try.
///   * [classifyProbeBody] reads a probe response body into a [ProbeResult].
///   * [probeServer] runs ONE candidate over the network (short timeout,
///     redirects OFF, lightweight http client) using the two-request protocol.
///   * [resolveServer] walks the ladder and returns the best [ResolvedServer].
///
/// The network bits take their `http.Client` and timeout by parameter so the
/// resolver can be driven entirely in-memory from unit tests.

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Per-candidate auth posture, derived from the two-request probe.
enum ProbeAuthMode {
  /// `aboutServer` returned data AND the @RequireAuth probe returned data —
  /// the server is reachable with no auth (or we're already authorised).
  open,

  /// `aboutServer` returned data but the @RequireAuth probe came back
  /// "Unauthorized" — a real Suwayomi server that needs credentials.
  authRequired,
}

/// The classified outcome of probing one candidate URL.
///
/// `confirmed` is the strong signal: we saw a real Suwayomi `aboutServer`
/// payload. `reached` means the host answered with *something* HTTP-shaped but
/// not a Suwayomi GraphQL body (could be a reverse proxy login page, a 401
/// HTML page, the wrong service, …). `basicGated` is the special case where
/// the transport itself is gated by HTTP Basic auth (a 401 with a
/// `WWW-Authenticate: Basic` challenge) — we cannot see past it to confirm
/// Suwayomi, so per spec it must NEVER short-circuit and NEVER read as found.
class ProbeResult {
  const ProbeResult({
    required this.url,
    required this.confirmed,
    required this.reached,
    required this.basicGated,
    this.authMode,
    this.serverName,
    this.serverVersion,
  });

  /// Nothing answered at this candidate (socket error / timeout / no body).
  const ProbeResult.notReached(this.url)
      : confirmed = false,
        reached = false,
        basicGated = false,
        authMode = null,
        serverName = null,
        serverVersion = null;

  /// The host answered but it was not a confirmable Suwayomi GraphQL body.
  const ProbeResult.reachedUnconfirmed(this.url)
      : confirmed = false,
        reached = true,
        basicGated = false,
        authMode = null,
        serverName = null,
        serverVersion = null;

  /// The transport is behind HTTP Basic auth — opaque, cannot confirm.
  const ProbeResult.basicGatedResult(this.url)
      : confirmed = false,
        reached = true,
        basicGated = true,
        authMode = null,
        serverName = null,
        serverVersion = null;

  final String url;

  /// We saw a genuine Suwayomi `aboutServer` payload at this URL.
  final bool confirmed;

  /// The host responded with *something* (not a transport failure).
  final bool reached;

  /// A 401 + `WWW-Authenticate: Basic` challenge fronts this URL.
  final bool basicGated;

  /// When [confirmed], whether the server's @RequireAuth surface needs creds.
  final ProbeAuthMode? authMode;

  /// `aboutServer.name`, when present in the body (read independently of
  /// the `errors[]` array — a partial/errored response can still carry it).
  final String? serverName;

  /// `aboutServer.version`, when present in the body.
  final String? serverVersion;
}

/// The final answer the UI consumes.
class ResolvedServer {
  const ResolvedServer({
    required this.baseUrl,
    required this.outcome,
    this.authMode,
    this.serverName,
    this.serverVersion,
  });

  /// The base URL the UI should adopt (no `/api/graphql` suffix).
  final String baseUrl;

  /// How strong the match is — see [ResolveOutcome].
  final ResolveOutcome outcome;

  /// For a [ResolveOutcome.found] result, whether the server needs auth.
  final ProbeAuthMode? authMode;

  final String? serverName;
  final String? serverVersion;

  bool get isFound => outcome == ResolveOutcome.found;
}

/// Strength of the resolver's best result, in descending confidence.
enum ResolveOutcome {
  /// Confirmed Suwayomi server (`aboutServer` payload seen).
  found,

  /// Best we could reach is behind HTTP Basic auth — can't confirm Suwayomi,
  /// but there IS a server here. The UI prompts for basic creds.
  basicGated,

  /// Something answered but we couldn't confirm it's Suwayomi.
  reachedUnconfirmed,

  /// Nothing answered at any candidate.
  notReached,
}

// ---------------------------------------------------------------------------
// Candidate ladder + normalisation
// ---------------------------------------------------------------------------

/// Default Suwayomi port, surfaced on bare hosts so the user sees/edits it.
const int kDefaultSuwayomiPort = 4567;

/// Builds the ordered list of concrete base URLs to try for [rawInput].
///
/// Rules (red-teamed):
///   * Trim, and treat blank as no candidates.
///   * IPv6 literals are detected FIRST (bracketed `[::1]` or a bare literal
///     that [Uri.parseIPv6Address] accepts) BEFORE any `host:port` split, so a
///     bare `::1` / `fe80::1` is never mistaken for `host` + `port`.
///   * An explicit scheme (`http://` / `https://`) is honoured verbatim and
///     yields exactly ONE candidate — the user told us what they want.
///   * A scheme-less input with NO typed port fans out http-first (spec
///     decision #2, the LAN fast-path):
///       http://host:4567, https://host, http://host
///   * A scheme-less input WITH a typed port keeps that port on both schemes
///     and skips the default-port / bare-host variants (spec Part A):
///       http://host:port, https://host:port
///   * Any base path the user typed is preserved on every candidate.
///   * URLs are assembled via [Uri] (never string concatenation); a part that
///     can't form a valid URL is dropped (never throws); the list is
///     de-duplicated, order-preserving.
List<String> connectionCandidates(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) return const [];

  // --- Explicit scheme. ---
  final lower = input.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty) return const [];
    if (uri.hasPort) {
      // Scheme AND port → fully specified; honour it verbatim (custom ports).
      return _dedup([_assemble(uri.scheme, uri.host, uri.port, uri.path)]);
    }
    // Scheme but NO port → the user named a host, not a full address. Try the
    // default Suwayomi port FIRST (a server is rarely on :80/:443 bare), then
    // the scheme's bare port as a fallback.
    return _dedup([
      _assemble(uri.scheme, uri.host, kDefaultSuwayomiPort, uri.path),
      _assemble(uri.scheme, uri.host, null, uri.path),
    ]);
  }

  // Split off any base path the user typed (everything from the first '/').
  String authority = input;
  String path = '';
  final slash = input.indexOf('/');
  if (slash >= 0) {
    authority = input.substring(0, slash);
    path = input.substring(slash); // keeps the leading '/'
  }
  if (authority.isEmpty) return const [];

  final (host, port) = _splitHostPort(authority);
  if (host.isEmpty) return const [];

  if (port != null) {
    // Explicit port: only the two scheme variants on that exact port; the
    // 4567/443/80 substitutions are skipped (spec Part A, round-3 fix).
    return _dedup([
      _assemble('http', host, port, path),
      _assemble('https', host, port, path),
    ]);
  }

  // No port: http on the default Suwayomi port first (LAN), then bare https
  // (:443, reverse-proxy), then bare http (:80).
  return _dedup([
    _assemble('http', host, kDefaultSuwayomiPort, path),
    _assemble('https', host, null, path),
    _assemble('http', host, null, path),
  ]);
}

/// Splits a scheme-less authority into `(host, port?)`, handling IPv6 FIRST so
/// a bare IPv6 literal's colons are never read as a port separator.
(String, int?) _splitHostPort(String authority) {
  // Bracketed IPv6: [::1] or [fe80::1]:4568
  if (authority.startsWith('[')) {
    final close = authority.indexOf(']');
    if (close < 0) return (authority, null); // malformed; pass through
    final host = authority.substring(1, close); // inner literal, no brackets
    final rest = authority.substring(close + 1);
    if (rest.startsWith(':')) {
      final p = int.tryParse(rest.substring(1));
      return (host, p);
    }
    return (host, null);
  }

  // Bare IPv6 literal (e.g. `::1`, `fe80::1`) — accepted by parseIPv6Address.
  // Detect BEFORE the host:port split: such a literal has 2+ colons and must
  // not be split on its last colon.
  if (_isBareIpv6(authority)) {
    return (authority, null);
  }

  // IPv4 / hostname: split on the single (last) colon if present.
  final colon = authority.lastIndexOf(':');
  if (colon >= 0) {
    final host = authority.substring(0, colon);
    final p = int.tryParse(authority.substring(colon + 1));
    // Only treat the suffix as a port when it's numeric AND in range. A
    // non-numeric ('host:abc') or out-of-range ('host:99999') suffix is not a
    // port — return the whole authority as host so the bad candidate is
    // dropped by [_assemble] rather than wasting a probe on a default port.
    if (p == null || p < 1 || p > 65535) return (authority, null);
    return (host, p);
  }
  return (authority, null);
}

bool _isBareIpv6(String s) {
  // A valid bare IPv6 literal contains '::' or has multiple ':' segments.
  // parseIPv6Address is the authority; guard it with a try.
  if (!s.contains(':')) return false;
  try {
    Uri.parseIPv6Address(s);
    return true;
  } catch (_) {
    return false;
  }
}

/// Assembles a base URL from parts via [Uri] — never string concatenation.
/// [host] may be an IPv6 literal WITHOUT brackets; [Uri] re-brackets it.
///
/// Returns `null` (rather than throwing) when the parts can't form a valid URL
/// — e.g. a host still carrying a stray `:` or userinfo `@` from a malformed
/// input like `host:abc` or `user@host:4567`. [connectionCandidates] filters
/// these out, so arbitrary user text never crashes the resolver.
String? _assemble(String scheme, String host, int? port, String path) {
  // Normalise the path: drop a lone trailing slash so `host/` and `host`
  // produce the same candidate, but keep a real base path (e.g. `/suwayomi`).
  var p = path;
  if (p == '/') p = '';
  if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);

  try {
    final uri = Uri(
      scheme: scheme,
      host: host,
      port: port,
      path: p.isEmpty ? '' : p,
    );
    // Uri.toString() omits a default port for the scheme; that's fine — it
    // keeps explicit non-default ports and drops redundant ones, de-dups well.
    return uri.toString();
  } on FormatException {
    return null;
  }
}

List<String> _dedup(List<String?> urls) {
  final seen = <String>{};
  final out = <String>[];
  for (final u in urls) {
    if (u != null && seen.add(u)) out.add(u);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Probe queries
// ---------------------------------------------------------------------------

/// Auth-exempt confirmation query: a real Suwayomi server answers this with
/// `data.aboutServer{name,version}` whether or not auth is configured.
const String kAboutProbeQuery = 'query { aboutServer { name version } }';

/// @RequireAuth probe: `downloadStatus` is gated server-side. Unauthenticated,
/// the server returns an `errors[]` entry whose message is exactly
/// "Unauthorized"; authenticated (or auth-disabled) it returns data.
const String kAuthProbeQuery = 'query { downloadStatus { __typename } }';

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

/// Reads the [aboutBody] (response body of [kAboutProbeQuery]) and the
/// [authBody] (response body of [kAuthProbeQuery]) into a [ProbeResult].
///
/// KEY RULES (red-teamed):
///   * `aboutServer.name`/`.version` are read INDEPENDENTLY of `errors[]`: a
///     response can carry partial data alongside errors and we still treat a
///     present `aboutServer` as confirmation.
///   * `authRequired` is "does the auth-probe body contain (case-insensitive)
///     the substring 'unauthor' in its errors". This catches both
///     "Unauthorized" and "Unauthorised"/"unauthorized access".
///   * If the about-probe doesn't yield an `aboutServer` object, the candidate
///     is NOT confirmed (returns null here → caller treats as reached-unconfirmed).
ProbeResult? classifyProbeBody({
  required String url,
  required String aboutBody,
  required String authBody,
}) {
  final about = _tryDecode(aboutBody);
  if (about == null) return null;

  final aboutServer = _readAboutServer(about);
  if (aboutServer == null) return null; // not a Suwayomi GraphQL body

  final name = aboutServer['name'];
  final version = aboutServer['version'];

  final authRequired = _bodyIndicatesUnauthorised(authBody);

  return ProbeResult(
    url: url,
    confirmed: true,
    reached: true,
    basicGated: false,
    authMode: authRequired ? ProbeAuthMode.authRequired : ProbeAuthMode.open,
    serverName: name is String ? name : null,
    serverVersion: version is String ? version : null,
  );
}

Map<String, dynamic>? _tryDecode(String body) {
  if (body.isEmpty) return null;
  try {
    final decoded = json.decode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Pulls `data.aboutServer` out of a decoded GraphQL body, independently of
/// the presence of `errors[]`. Returns null if absent.
Map<String, dynamic>? _readAboutServer(Map<String, dynamic> body) {
  final data = body['data'];
  if (data is! Map<String, dynamic>) return null;
  final about = data['aboutServer'];
  return about is Map<String, dynamic> ? about : null;
}

/// True when the auth-probe body's `errors[]` contains a message with the
/// case-insensitive substring 'unauthor'.
bool _bodyIndicatesUnauthorised(String authBody) {
  final decoded = _tryDecode(authBody);
  if (decoded == null) {
    // Couldn't parse — fall back to a raw substring scan so a non-JSON 401
    // page ("401 Unauthorized") still trips the flag.
    return authBody.toLowerCase().contains('unauthor');
  }
  final errors = decoded['errors'];
  if (errors is! List) return false;
  for (final e in errors) {
    if (e is Map) {
      final msg = e['message'];
      if (msg is String && msg.toLowerCase().contains('unauthor')) return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Network probe (one candidate)
// ---------------------------------------------------------------------------

/// Builds the `/api/graphql` URL for a candidate base URL, via [Uri] so a
/// base path is preserved and the segment is appended structurally.
Uri graphqlUriFor(String baseUrl) {
  final base = Uri.parse(baseUrl);
  return base.replace(pathSegments: [...base.pathSegments, 'api', 'graphql']);
}

/// Inverse of [graphqlUriFor]: given a redirect destination that points at a
/// GraphQL endpoint, recover the server's base URL by stripping a trailing
/// `api/graphql`. A destination that ISN'T a graphql endpoint (e.g. an SSO
/// `/login`) is returned as-is — re-probing it will simply not confirm.
String _baseFromGraphqlUri(Uri g) {
  var segs = g.pathSegments.toList();
  if (segs.length >= 2 &&
      segs[segs.length - 1] == 'graphql' &&
      segs[segs.length - 2] == 'api') {
    segs = segs.sublist(0, segs.length - 2);
  }
  // Rebuild from parts so query/fragment are dropped without leaving a stray
  // "?#" in the string form.
  return Uri(
    scheme: g.scheme,
    host: g.host,
    port: g.hasPort ? g.port : null,
    pathSegments: segs,
  ).toString();
}

/// Probes ONE candidate base URL using the two-request protocol with a short
/// [timeout] and redirects OFF (so an https→http downgrade or a proxy login
/// redirect can't masquerade as a reachable Suwayomi server). [client] is
/// injected for testability.
///
/// Request A confirms Suwayomi (`aboutServer`); request B detects auth
/// (`downloadStatus`). A 401 with a `WWW-Authenticate: Basic` challenge on
/// request A short-circuits to a [ProbeResult.basicGatedResult] — we cannot
/// see past Basic auth to confirm Suwayomi.
Future<ProbeResult> probeServer(
  String baseUrl, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 4),
  int redirectBudget = 1,
}) async {
  final uri = graphqlUriFor(baseUrl);

  final http.StreamedResponse aboutResp;
  final String aboutBody;
  try {
    final (resp, body) = await _sendNoRedirect(
      client,
      uri,
      kAboutProbeQuery,
      timeout,
    );
    aboutResp = resp;
    aboutBody = body;
  } catch (_) {
    return ProbeResult.notReached(baseUrl);
  }

  // HTTP Basic auth fronting the transport: opaque, can't confirm Suwayomi.
  if (aboutResp.statusCode == 401 &&
      (aboutResp.headers['www-authenticate']?.toLowerCase().contains('basic') ??
          false)) {
    return ProbeResult.basicGatedResult(baseUrl);
  }

  // A redirect: follow ONE hop to the destination (a proxy bouncing the API to
  // its real origin is legitimate), but NEVER chase an https→http downgrade and
  // NEVER chase a second hop (an SSO portal that keeps bouncing). On the single
  // hop we persist the DESTINATION base on confirm, not the redirecting URL.
  if (aboutResp.statusCode >= 300 && aboutResp.statusCode < 400) {
    final loc = aboutResp.headers['location'];
    if (loc != null && loc.isNotEmpty && redirectBudget > 0) {
      Uri? dest;
      try {
        dest = uri.resolveUri(Uri.parse(loc));
      } catch (_) {
        dest = null;
      }
      if (dest != null && !(uri.isScheme('https') && dest.isScheme('http'))) {
        return probeServer(
          _baseFromGraphqlUri(dest),
          client: client,
          timeout: timeout,
          redirectBudget: redirectBudget - 1,
        );
      }
    }
    return ProbeResult.reachedUnconfirmed(baseUrl);
  }

  // Auth probe (request B). Failure here doesn't sink the candidate — we can
  // still confirm Suwayomi from request A and assume auth-required if B is
  // unreadable.
  String? authBody;
  try {
    final (_, body) = await _sendNoRedirect(
      client,
      uri,
      kAuthProbeQuery,
      timeout,
    );
    authBody = body;
  } catch (_) {
    authBody = null;
  }

  final classified = classifyProbeBody(
      url: baseUrl, aboutBody: aboutBody, authBody: authBody ?? '');
  if (classified != null) {
    if (authBody == null && classified.confirmed) {
      // B unreadable: we can't prove the server is open, and reading it as
      // open would onboard an auth server with no login step.
      return ProbeResult(
        url: classified.url,
        confirmed: true,
        reached: true,
        basicGated: false,
        authMode: ProbeAuthMode.authRequired,
        serverName: classified.serverName,
        serverVersion: classified.serverVersion,
      );
    }
    return classified;
  }

  return ProbeResult.reachedUnconfirmed(baseUrl);
}

/// Sends one POST with redirects disabled and a hard timeout, returning the
/// streamed response plus its decoded body string.
Future<(http.StreamedResponse, String)> _sendNoRedirect(
  http.Client client,
  Uri uri,
  String query,
  Duration timeout,
) async {
  final request = http.Request('POST', uri)
    ..followRedirects = false
    ..headers['Content-Type'] = 'application/json'
    ..body = jsonEncode({'query': query});
  final streamed = await client.send(request).timeout(timeout);
  final body = await streamed.stream.bytesToString().timeout(timeout);
  return (streamed, body);
}

// ---------------------------------------------------------------------------
// Resolve (walk the ladder)
// ---------------------------------------------------------------------------

/// Walks [connectionCandidates] for [rawInput] in order and returns the best
/// [ResolvedServer].
///
/// Short-circuit + fallback rules (red-teamed):
///   * A CONFIRMED candidate short-circuits immediately — first confirmed wins.
///     Ladder order is http-first (spec decision #2, the LAN fast-path); the
///     resolved URL is surfaced for the user to confirm, so the http-first
///     pick is visible rather than a silent downgrade.
///   * A basic-gated candidate NEVER short-circuits and is NEVER reported as
///     `found`: we keep walking in case a LATER candidate is a confirmable
///     Suwayomi server (e.g. http:4567 is basic-gated but https is the real one).
///   * If no candidate is confirmed, fall back by priority:
///       basicGated > reachedUnconfirmed > notReached.
Future<ResolvedServer> resolveServer(
  String rawInput, {
  required http.Client client,
  Duration perCandidateTimeout = const Duration(seconds: 4),
  Future<ProbeResult> Function(String url)? probe,
}) async {
  final candidates = connectionCandidates(rawInput);
  if (candidates.isEmpty) {
    // Unparseable input (e.g. a typo'd port): nothing to probe. Hand back a
    // best-effort scheme-bearing URL so the "use this address anyway" escape
    // never persists raw schemeless text (spec Part D).
    return ResolvedServer(
      baseUrl: normalisedFallbackUrl(rawInput),
      outcome: ResolveOutcome.notReached,
    );
  }

  final doProbe = probe ??
      (url) => probeServer(url, client: client, timeout: perCandidateTimeout);

  ProbeResult? bestBasicGated;
  ProbeResult? bestReached;

  for (final candidate in candidates) {
    final result = await doProbe(candidate);

    if (result.confirmed) {
      // First confirmed candidate wins outright.
      return ResolvedServer(
        baseUrl: result.url,
        outcome: ResolveOutcome.found,
        authMode: result.authMode,
        serverName: result.serverName,
        serverVersion: result.serverVersion,
      );
    }
    if (result.basicGated) {
      bestBasicGated ??= result; // remember, but keep walking
      continue;
    }
    if (result.reached) {
      bestReached ??= result;
    }
  }

  if (bestBasicGated != null) {
    return ResolvedServer(
      baseUrl: bestBasicGated.url,
      outcome: ResolveOutcome.basicGated,
    );
  }
  if (bestReached != null) {
    return ResolvedServer(
      baseUrl: bestReached.url,
      outcome: ResolveOutcome.reachedUnconfirmed,
    );
  }
  return ResolvedServer(
    baseUrl: candidates.first,
    outcome: ResolveOutcome.notReached,
  );
}

/// Renders a base URL with its port ALWAYS explicit, so result messages can be
/// unambiguous about exactly where (and on which port) a server was reached —
/// e.g. `http://192.168.0.10` becomes `http://192.168.0.10:80`. Dart's `Uri`
/// hides scheme-default ports; this surfaces them. IPv6 hosts are bracketed.
String displayAddress(String baseUrl) {
  final u = Uri.tryParse(baseUrl);
  if (u == null || u.host.isEmpty) return baseUrl;
  final host = u.host.contains(':') ? '[${u.host}]' : u.host;
  return '${u.scheme}://$host:${u.port}${u.path}';
}

/// Whether a failed resolve should suggest "try its https address" — true only
/// when NO https candidate was tried (the user pinned an explicit `http://`).
/// A bare host already includes an https candidate, so we don't nag.
bool shouldSuggestHttps(String rawInput) => !connectionCandidates(rawInput)
    .any((c) => c.toLowerCase().startsWith('https://'));

/// Best-effort scheme-bearing form of [rawInput] for the "use this address
/// anyway" escape — guarantees a scheme so we never persist raw schemeless
/// text. Prefers the first real candidate; otherwise prefixes `http://`.
String normalisedFallbackUrl(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) return input;
  final lower = input.toLowerCase();
  // Explicit scheme → "use this address anyway" means EXACTLY what they typed.
  if (lower.startsWith('http://') || lower.startsWith('https://')) return input;
  // No scheme → first candidate (scheme + default port), else http:// prefix.
  final first = connectionCandidates(input);
  if (first.isNotEmpty) return first.first;
  return 'http://$input';
}

/// Web "Test connection" auth detection. The full [probeServer] protocol can't
/// run in a browser (redirects can't be switched off), but the auth probe
/// itself can: POST [kAuthProbeQuery] with redirects left on and read the
/// body. Unreadable / 401 / 403 reads as auth-required — the caller has
/// already confirmed `aboutServer`, and a dead read here must never onboard an
/// auth server without its login step.
Future<bool> webAuthRequired(
  String baseUrl, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final uri = graphqlUriFor(baseUrl);
  try {
    final resp = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': kAuthProbeQuery}),
        )
        .timeout(timeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) return true;
    return _bodyIndicatesUnauthorised(resp.body);
  } catch (_) {
    return true;
  }
}

// ---------------------------------------------------------------------------
// VERIFIED try-both (submit-time auth resolution)
// ---------------------------------------------------------------------------

/// The auth mode whose credential ACTUALLY authorised an `@RequireAuth` API
/// call — the only trustworthy signal for simple-vs-ui (round-4 fix).
enum VerifiedAuthMode { simpleLogin, uiLogin }

/// Sends the `@RequireAuth` probe ([kAuthProbeQuery]) carrying a credential and
/// reports whether the server ACTUALLY authorised it.
///
/// This is the heart of the round-4 fix: Suwayomi's `POST /login.html` returns
/// 303 + a session cookie in EVERY auth mode — including `ui_login`, where that
/// cookie is then ignored. So a successful simple-login is NOT proof the server
/// is in simple_login mode. We must push the obtained credential through a real
/// protected query and let the server's own `getUserFromContext` be the judge:
/// authorised (data, no "unauthorized") → the credential is the right kind.
///
/// Pass EXACTLY one of [cookie] / [bearer] / [basic]. [basic] is the raw
/// `username:password` pair (base64-encoded here into a `Basic` header) — used
/// to prove a basic_auth credential ACTUALLY authorises the @RequireAuth
/// surface, not just the public `aboutServer`. Redirects are disabled and any
/// transport failure reads as "not authorised" (false), never a throw.
Future<bool> authProbeAuthorized(
  String baseUrl, {
  required http.Client client,
  String? cookie,
  String? bearer,
  String? basic,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final uri = graphqlUriFor(baseUrl);
  try {
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'query': kAuthProbeQuery});
    if (cookie != null) request.headers['Cookie'] = cookie;
    if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
    if (basic != null) {
      request.headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode(basic))}';
    }
    final streamed = await client.send(request).timeout(timeout);
    final body = await streamed.stream.bytesToString().timeout(timeout);
    if (streamed.statusCode == 401 || streamed.statusCode == 403) return false;
    // Authorised iff the body does not carry an "unauthorized" GraphQL error.
    return !_bodyIndicatesUnauthorised(body);
  } catch (_) {
    return false;
  }
}

/// Re-probes `aboutServer` carrying an HTTP Basic `Authorization` header and
/// reports whether it confirms a Suwayomi server. This is the basic_auth
/// equivalent of the simple/ui verified sign-in: a basic-gated host is opaque
/// until we send credentials, so submit re-probes WITH the Basic header —
/// 200 + a real `aboutServer` shape means the creds are valid AND it's really
/// Suwayomi (closes the "random 401 host" trap on the basic path). Any other
/// outcome (still 401, non-Suwayomi body, transport failure) → false.
Future<bool> basicAuthConfirms(
  String baseUrl, {
  required http.Client client,
  required String username,
  required String password,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final uri = graphqlUriFor(baseUrl);
  try {
    final cred = base64Encode(utf8.encode('$username:$password'));
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Basic $cred'
      ..body = jsonEncode({'query': kAboutProbeQuery});
    final streamed = await client.send(request).timeout(timeout);
    final body = await streamed.stream.bytesToString().timeout(timeout);
    if (streamed.statusCode != 200) return false;
    final decoded = _tryDecode(body);
    return decoded != null && _readAboutServer(decoded) != null;
  } catch (_) {
    return false;
  }
}

/// Runs the VERIFIED try-both for a server that we already confirmed is
/// Suwayomi-with-auth-required. [obtainSimpleCookie] performs the `/login.html`
/// POST and returns the session cookie (throws/returns null on rejection);
/// [obtainUiBearer] runs the `login` mutation and returns the access token.
/// Each obtained credential is VERIFIED via [authProbeAuthorized] before we
/// trust it, so a `ui_login` server (whose cookie is inert) never gets
/// mis-tagged simple_login.
///
/// Returns the verified mode, or null when neither credential authorises
/// (wrong password, or not really a Suwayomi auth server).
Future<VerifiedAuthMode?> verifyAuthMode({
  required String baseUrl,
  required http.Client client,
  required Future<String?> Function() obtainSimpleCookie,
  required Future<String?> Function() obtainUiBearer,
  Duration timeout = const Duration(seconds: 4),
}) async {
  // 1. simple-login → cookie → re-probe carrying ONLY that cookie.
  String? cookie;
  try {
    cookie = await obtainSimpleCookie();
  } catch (_) {
    cookie = null;
  }
  if (cookie != null &&
      cookie.isNotEmpty &&
      await authProbeAuthorized(baseUrl,
          client: client, cookie: cookie, timeout: timeout)) {
    return VerifiedAuthMode.simpleLogin;
  }

  // 2. ui-login → bearer → re-probe carrying ONLY that bearer (a fresh request,
  //    no stale cookie from step 1 — see [authProbeAuthorized]).
  String? bearer;
  try {
    bearer = await obtainUiBearer();
  } catch (_) {
    bearer = null;
  }
  if (bearer != null &&
      bearer.isNotEmpty &&
      await authProbeAuthorized(baseUrl,
          client: client, bearer: bearer, timeout: timeout)) {
    return VerifiedAuthMode.uiLogin;
  }

  return null;
}
