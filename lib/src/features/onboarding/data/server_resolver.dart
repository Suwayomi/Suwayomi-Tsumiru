// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../constants/enum.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../../utils/platform/web_auth_mode.dart';



enum ProbeAuthMode {
  /// Both aboutServer and the protected probe returned data.
  open,

  /// aboutServer confirmed Suwayomi, but the protected probe requires credentials.
  authRequired,
}

/// Basic-gated hosts remain unconfirmed; only an aboutServer payload proves Suwayomi.
class ProbeResult {
  const ProbeResult({
    required this.url,
    required this.confirmed,
    required this.reached,
    required this.basicGated,
    this.authMode,
    this.detectedAuthType,
    this.serverName,
    this.serverVersion,
  });

  const ProbeResult.notReached(this.url)
    : confirmed = false,
      reached = false,
      basicGated = false,
      authMode = null,
      detectedAuthType = null,
      serverName = null,
      serverVersion = null;

  const ProbeResult.reachedUnconfirmed(this.url)
    : confirmed = false,
      reached = true,
      basicGated = false,
      authMode = null,
      detectedAuthType = null,
      serverName = null,
      serverVersion = null;

  const ProbeResult.basicGatedResult(this.url)
    : confirmed = false,
      reached = true,
      basicGated = true,
      authMode = null,
      detectedAuthType = null,
      serverName = null,
      serverVersion = null;

  final String url;

  final bool confirmed;

  final bool reached;

  final bool basicGated;

  final ProbeAuthMode? authMode;

  /// Null when responses do not identify an auth method.
  final AuthType? detectedAuthType;

  /// Read even with errors alongside partial data.
  final String? serverName;

  final String? serverVersion;
}

class ResolvedServer {
  const ResolvedServer({
    required this.baseUrl,
    required this.outcome,
    this.authMode,
    this.detectedAuthType,
    this.serverName,
    this.serverVersion,
  });

  /// Base URL without /api/graphql.
  final String baseUrl;

  final ResolveOutcome outcome;

  final ProbeAuthMode? authMode;

  /// Null leaves the sign-in method at its Basic default.
  final AuthType? detectedAuthType;

  final String? serverName;
  final String? serverVersion;

  bool get isFound => outcome == ResolveOutcome.found;
}

enum ResolveOutcome {
  found,

  /// Basic auth hides service identity; credentials are needed to confirm Suwayomi.
  basicGated,

  reachedUnconfirmed,

  notReached,
}


const int kDefaultSuwayomiPort = 4567;

/// Returns deduplicated probe URLs in preference order, preserving typed ports and base paths.
List<String> connectionCandidates(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) return const [];

  final lower = input.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty) return const [];
    if (uri.hasPort) {
      return _dedup([_assemble(uri.scheme, uri.host, uri.port, uri.path)]);
    }
    // An explicit scheme without a port still tries the default Suwayomi port first.
    return _dedup([
      _assemble(uri.scheme, uri.host, kDefaultSuwayomiPort, uri.path),
      _assemble(uri.scheme, uri.host, null, uri.path),
    ]);
  }

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
    // Preserve an explicit port across both schemes; do not substitute ports.
    return _dedup([
      _assemble('http', host, port, path),
      _assemble('https', host, port, path),
    ]);
  }

  return _dedup([
    _assemble('http', host, kDefaultSuwayomiPort, path),
    _assemble('https', host, null, path),
    _assemble('http', host, null, path),
  ]);
}

(String, int?) _splitHostPort(String authority) {
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

  // Detect IPv6 before splitting host:port; its colons belong to the address.
  if (_isBareIpv6(authority)) {
    return (authority, null);
  }

  final colon = authority.lastIndexOf(':');
  if (colon >= 0) {
    final host = authority.substring(0, colon);
    final p = int.tryParse(authority.substring(colon + 1));
    // Invalid port suffixes remain in the host so _assemble rejects them instead of probing a default port.
    if (p == null || p < 1 || p > 65535) return (authority, null);
    return (host, p);
  }
  return (authority, null);
}

bool _isBareIpv6(String s) {
  if (!s.contains(':')) return false;
  try {
    Uri.parseIPv6Address(s);
    return true;
  } catch (_) {
    return false;
  }
}

// Uri brackets bare IPv6 hosts; malformed parts return null instead of throwing.
String? _assemble(String scheme, String host, int? port, String path) {
  // Drop a lone trailing slash but preserve a real base path.
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


// aboutServer is auth-exempt and confirms Suwayomi even when auth is configured.
const String kAboutProbeQuery = 'query { aboutServer { name version } }';

// downloadStatus requires auth and reports Unauthorized in GraphQL errors when denied.
const String kAuthProbeQuery = 'query { downloadStatus { __typename } }';


/// Confirms aboutServer even with partial-data errors; auth errors match "unauthor" case-insensitively.
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

Map<String, dynamic>? _readAboutServer(Map<String, dynamic> body) {
  final data = body['data'];
  if (data is! Map<String, dynamic>) return null;
  final about = data['aboutServer'];
  return about is Map<String, dynamic> ? about : null;
}

bool _bodyIndicatesUnauthorised(String authBody) {
  final decoded = _tryDecode(authBody);
  if (decoded == null) {
    // Non-JSON 401 pages can still contain an Unauthorized message.
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


/// Detects auth from a redirect-OFF root response; null means the responses cannot identify a mode.
AuthType? detectAuthType({
  required int probeStatus,
  String? wwwAuthenticate,
  bool? probeUnauthorized,
  int? rootStatus,
  String? rootLocation,
}) {
  if ((probeStatus == 401 || probeStatus == 404) &&
      (wwwAuthenticate?.toLowerCase().startsWith('basic') ?? false)) {
    return AuthType.basic;
  }

  if (probeStatus == 200 && probeUnauthorized == true) {
    // Only a redirect to the login page identifies simple login.
    if (rootStatus == 301 ||
        rootStatus == 302 ||
        rootStatus == 303 ||
        rootStatus == 307 ||
        rootStatus == 308) {
      return (rootLocation?.contains('login.html') ?? false)
          ? AuthType.simpleLogin
          : null;
    }
    // Without an observable login redirect, UI login is the compatible fallback.
    if (rootStatus == 200 || rootStatus == null) return AuthType.uiLogin;
  }

  return null;
}


/// Appends /api/graphql structurally, preserving the server base path.
Uri graphqlUriFor(String baseUrl) {
  final base = Uri.parse(baseUrl);
  return base.replace(pathSegments: [...base.pathSegments, 'api', 'graphql']);
}

/// Strips a trailing api/graphql from redirects; other destinations remain unchanged.
String _baseFromGraphqlUri(Uri g) {
  var segs = g.pathSegments.toList();
  if (segs.length >= 2 &&
      segs[segs.length - 1] == 'graphql' &&
      segs[segs.length - 2] == 'api') {
    segs = segs.sublist(0, segs.length - 2);
  }
  return Uri(
    scheme: g.scheme,
    host: g.host,
    port: g.hasPort ? g.port : null,
    pathSegments: segs,
  ).toString();
}

/// Confirms Suwayomi and probes protected auth; a Basic challenge remains unconfirmed.
Future<ProbeResult> probeServer(
  String baseUrl, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 4),
  int redirectBudget = 1,
  Map<String, String>? extraHeaders,
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
      extraHeaders: extraHeaders,
    );
    aboutResp = resp;
    aboutBody = body;
  } catch (_) {
    return ProbeResult.notReached(baseUrl);
  }

  // Preview servers answer 404 with a Basic challenge instead of 401.
  if ((aboutResp.statusCode == 401 || aboutResp.statusCode == 404) &&
      (aboutResp.headers['www-authenticate']?.toLowerCase().contains('basic') ??
          false)) {
    return ProbeResult(
      url: baseUrl,
      confirmed: false,
      reached: true,
      basicGated: true,
      authMode: null,
      detectedAuthType: AuthType.basic,
    );
  }

  // Follow one redirect only, reject HTTPS downgrades, and adopt the confirmed destination base.
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
          extraHeaders: extraHeaders,
        );
      }
    }
    return ProbeResult.reachedUnconfirmed(baseUrl);
  }

  // An unreadable protected probe still allows confirmation but cannot prove auth is disabled.
  int? authStatus;
  String? authWwwAuthenticate;
  String? authBody;
  try {
    final (resp, body) = await _sendNoRedirect(
      client,
      uri,
      kAuthProbeQuery,
      timeout,
      extraHeaders: extraHeaders,
    );
    authStatus = resp.statusCode;
    authWwwAuthenticate = resp.headers['www-authenticate'];
    authBody = body;
  } catch (_) {
    authBody = null;
  }

  final classified = classifyProbeBody(
    url: baseUrl,
    aboutBody: aboutBody,
    authBody: authBody ?? '',
  );
  if (classified != null) {
    if (authBody == null && classified.confirmed) {
      // Fail closed when the protected probe is unreadable.
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

    // Read Basic challenges from request B; only an observed root hop can distinguish login modes.
    AuthType? detected;
    final status = authStatus;
    if (status != null) {
      final probeUnauthorized = _bodyIndicatesUnauthorised(authBody ?? '');
      if (status == 200 && probeUnauthorized) {
        final root = await readRootStatus(
          baseUrl,
          client: client,
          timeout: timeout,
          extraHeaders: extraHeaders,
        );
        if (root != null) {
          detected = detectAuthType(
            probeStatus: status,
            wwwAuthenticate: authWwwAuthenticate,
            probeUnauthorized: probeUnauthorized,
            rootStatus: root.$1,
            rootLocation: root.$2,
          );
        }
      } else {
        detected = detectAuthType(
          probeStatus: status,
          wwwAuthenticate: authWwwAuthenticate,
          probeUnauthorized: probeUnauthorized,
        );
      }
    }

    return ProbeResult(
      url: classified.url,
      confirmed: classified.confirmed,
      reached: classified.reached,
      basicGated: classified.basicGated,
      // A Basic challenge requires login even if its body is empty.
      authMode: detected == AuthType.basic
          ? ProbeAuthMode.authRequired
          : classified.authMode,
      detectedAuthType: detected,
      serverName: classified.serverName,
      serverVersion: classified.serverVersion,
    );
  }

  return ProbeResult.reachedUnconfirmed(baseUrl);
}

Future<(http.StreamedResponse, String)> _sendNoRedirect(
  http.Client client,
  Uri uri,
  String query,
  Duration timeout, {
  Map<String, String>? extraHeaders,
}) async {
  final request = http.Request('POST', uri)
    ..followRedirects = false
    ..headers['Content-Type'] = 'application/json'
    ..body = jsonEncode({'query': query});
  if (extraHeaders != null && extraHeaders.isNotEmpty) {
    for (final entry in extraHeaders.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'authorization' || lower == 'cookie') continue;
      request.headers[entry.key] = entry.value;
    }
  }
  final streamed = await client.send(request).timeout(timeout);
  final body = await streamed.stream.bytesToString().timeout(timeout);
  return (streamed, body);
}

// Without redirects, simple login returns 303 to /login.html; UI login serves the shell.
Future<(int, String?)?> readRootStatus(
  String baseUrl, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 4),
  Map<String, String>? extraHeaders,
}) async {
  try {
    // A trailing slash avoids proxy canonicalization masking the auth redirect.
    final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final request = http.Request('GET', Uri.parse(root))
      ..followRedirects = false;
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      for (final entry in extraHeaders.entries) {
        final lower = entry.key.toLowerCase();
        if (lower == 'authorization' || lower == 'cookie') continue;
        request.headers[entry.key] = entry.value;
      }
    }
    final streamed = await client.send(request).timeout(timeout);
    await streamed.stream.drain<void>().timeout(timeout);
    return (streamed.statusCode, streamed.headers['location']);
  } catch (_) {
    return null;
  }
}


/// First confirmed candidate wins; otherwise returns Basic-gated, unconfirmed, then unreachable.
Future<ResolvedServer> resolveServer(
  String rawInput, {
  required http.Client client,
  Duration perCandidateTimeout = const Duration(seconds: 4),
  Future<ProbeResult> Function(String url)? probe,
  Map<String, String>? extraHeaders,
}) async {
  final candidates = connectionCandidates(rawInput);
  if (candidates.isEmpty) {
    // The manual-address fallback must include a scheme even for malformed input.
    return ResolvedServer(
      baseUrl: normalisedFallbackUrl(rawInput),
      outcome: ResolveOutcome.notReached,
    );
  }

  final doProbe =
      probe ??
      (url) => probeServer(
        url,
        client: client,
        timeout: perCandidateTimeout,
        extraHeaders: extraHeaders,
      );

  ProbeResult? bestBasicGated;
  ProbeResult? bestReached;

  for (final candidate in candidates) {
    final result = await doProbe(candidate);

    if (result.confirmed) {
      return ResolvedServer(
        baseUrl: result.url,
        outcome: ResolveOutcome.found,
        authMode: result.authMode,
        detectedAuthType: result.detectedAuthType,
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
      detectedAuthType: bestBasicGated.detectedAuthType,
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

/// Shows scheme-default ports explicitly and brackets IPv6 hosts.
String displayAddress(String baseUrl) {
  final u = Uri.tryParse(baseUrl);
  if (u == null || u.host.isEmpty) return baseUrl;
  final host = u.host.contains(':') ? '[${u.host}]' : u.host;
  return '${u.scheme}://$host:${u.port}${u.path}';
}

/// Suggests HTTPS only when no HTTPS candidate was tried.
bool shouldSuggestHttps(String rawInput) => !connectionCandidates(
  rawInput,
).any((c) => c.toLowerCase().startsWith('https://'));

/// Returns the first requestable HTTP(S) candidate, or null for invalid input.
String? validServerBaseUrl(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) return null;
  final lower = input.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    try {
      final uri = Uri.parse(input);
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return input;
      }
    } catch (_) {}
    return null;
  }
  final candidates = connectionCandidates(input);
  return candidates.isEmpty ? null : candidates.first;
}

/// Manual-address fallback always includes a scheme, even for malformed input.
String normalisedFallbackUrl(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) return input;
  final lower = input.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return input;
  final first = connectionCandidates(input);
  if (first.isNotEmpty) return first.first;
  return 'http://$input';
}

/// Browser probes follow redirects; unreadable responses, 401, and 403 require auth.
Future<bool> webAuthRequired(
  String baseUrl, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 4),
  Map<String, String>? extraHeaders,
}) async {
  final probe = await webAuthProbe(
    baseUrl,
    client: client,
    timeout: timeout,
    extraHeaders: extraHeaders,
  );
  return probe.required;
}

/// Web cannot observe the root redirect; 200 + Unauthorized therefore selects UI login.
Future<({bool required, AuthType? detected})> webAuthProbe(
  String baseUrl, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 4),
  Map<String, String>? extraHeaders,
}) async {
  final uri = graphqlUriFor(baseUrl);
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (extraHeaders != null && extraHeaders.isNotEmpty) {
    for (final entry in extraHeaders.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'authorization' || lower == 'cookie') continue;
      headers[entry.key] = entry.value;
    }
  }
  try {
    final resp = await client
        .post(
          uri,
          headers: headers,
          body: jsonEncode({'query': kAuthProbeQuery}),
        )
        .timeout(timeout);
    final unauthorized =
        resp.statusCode == 401 ||
        resp.statusCode == 403 ||
        _bodyIndicatesUnauthorised(resp.body);
    return (
      required: unauthorized,
      detected: detectAuthType(
        probeStatus: resp.statusCode,
        wwwAuthenticate: resp.headers['www-authenticate'],
        probeUnauthorized: unauthorized,
        rootStatus: null,
      ),
    );
  } catch (_) {
    return (required: true, detected: null);
  }
}

bool webServerAuthUnsupported({
  required Object? aboutError,
  required AuthType? detectedAuthType,
}) {
  if (aboutError != null &&
      (isAuthenticationRequired(aboutError) ||
          isBasicGatedNotFound(aboutError))) {
    return true;
  }
  return isWebUnsupportedAuthMode(detectedAuthType);
}


/// Auth mode whose credential authorized a protected API call.
enum VerifiedAuthMode { simpleLogin, uiLogin }

/// Pass exactly one credential; verify a protected query because /login.html sets inert cookies in UI mode.
/// [basic] is raw username:password; redirects are disabled and failures return false.
Future<bool> authProbeAuthorized(
  String baseUrl, {
  required http.Client client,
  String? cookie,
  String? bearer,
  String? basic,
  Duration timeout = const Duration(seconds: 4),
  Map<String, String>? extraHeaders,
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
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      for (final entry in extraHeaders.entries) {
        final lower = entry.key.toLowerCase();
        if (lower == 'authorization' || lower == 'cookie') continue;
        request.headers[entry.key] = entry.value;
      }
    }
    final streamed = await client.send(request).timeout(timeout);
    final body = await streamed.stream.bytesToString().timeout(timeout);
    if (streamed.statusCode != 200) return false;
    final decoded = _tryDecode(body);
    if (decoded == null) return false;
    final errors = decoded['errors'];
    if (errors != null && (errors is! List || errors.isNotEmpty)) return false;
    final data = decoded['data'];
    if (data is! Map) return false;
    final status = data['downloadStatus'];
    return status is Map && status['__typename'] == 'DownloadStatus';
  } catch (_) {
    return false;
  }
}

/// Only HTTP 200 with Unauthorized errors proves token rejection.
Future<bool> authProbeExplicitlyRejects(
  String baseUrl, {
  required http.Client client,
  required String bearer,
  Duration timeout = const Duration(seconds: 4),
  Map<String, String>? extraHeaders,
}) async {
  final uri = graphqlUriFor(baseUrl);
  try {
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $bearer'
      ..body = jsonEncode({'query': kAuthProbeQuery});
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      for (final entry in extraHeaders.entries) {
        final lower = entry.key.toLowerCase();
        if (lower == 'authorization' || lower == 'cookie') continue;
        request.headers[entry.key] = entry.value;
      }
    }
    final streamed = await client.send(request).timeout(timeout);
    final body = await streamed.stream.bytesToString().timeout(timeout);
    if (streamed.statusCode != 200) return false;
    final decoded = _tryDecode(body);
    if (decoded == null) return false;
    final errors = decoded['errors'];
    if (errors is! List) return false;
    for (final e in errors) {
      if (e is Map) {
        final message = e['message'];
        if (message is String && message.toLowerCase().contains('unauthor')) {
          return true;
        }
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// Confirms a Basic-gated host with credentials; non-Suwayomi or failed responses return false.
Future<bool> basicAuthConfirms(
  String baseUrl, {
  required http.Client client,
  required String username,
  required String password,
  Duration timeout = const Duration(seconds: 4),
  Map<String, String>? extraHeaders,
}) async {
  final uri = graphqlUriFor(baseUrl);
  try {
    final cred = base64Encode(utf8.encode('$username:$password'));
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Basic $cred'
      ..body = jsonEncode({'query': kAboutProbeQuery});
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      for (final entry in extraHeaders.entries) {
        final lower = entry.key.toLowerCase();
        if (lower == 'authorization' || lower == 'cookie') continue;
        request.headers[entry.key] = entry.value;
      }
    }
    final streamed = await client.send(request).timeout(timeout);
    final body = await streamed.stream.bytesToString().timeout(timeout);
    if (streamed.statusCode != 200) return false;
    final decoded = _tryDecode(body);
    return decoded != null && _readAboutServer(decoded) != null;
  } catch (_) {
    return false;
  }
}

/// Verifies simple and UI credentials against a protected query; null means neither authorized.
Future<VerifiedAuthMode?> verifyAuthMode({
  required String baseUrl,
  required http.Client client,
  required Future<String?> Function() obtainSimpleCookie,
  required Future<String?> Function() obtainUiBearer,
  Duration timeout = const Duration(seconds: 4),
}) async {
  String? cookie;
  try {
    cookie = await obtainSimpleCookie();
  } catch (_) {
    cookie = null;
  }
  if (cookie != null &&
      cookie.isNotEmpty &&
      await authProbeAuthorized(
        baseUrl,
        client: client,
        cookie: cookie,
        timeout: timeout,
      )) {
    return VerifiedAuthMode.simpleLogin;
  }

  // Verify the bearer on a fresh request without the simple-login cookie.
  String? bearer;
  try {
    bearer = await obtainUiBearer();
  } catch (_) {
    bearer = null;
  }
  if (bearer != null &&
      bearer.isNotEmpty &&
      await authProbeAuthorized(
        baseUrl,
        client: client,
        bearer: bearer,
        timeout: timeout,
      )) {
    return VerifiedAuthMode.uiLogin;
  }

  return null;
}
