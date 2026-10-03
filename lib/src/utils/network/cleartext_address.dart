// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Whether requests to [url] would cross the internet unencrypted: plain
/// `http://` to a host that isn't on a private or local network. Every auth
/// mode then sends its secret in clear (the Basic password on each request,
/// the session cookie, the access and refresh tokens), and anyone on the path
/// can read it.
///
/// Plain HTTP on a home network stays allowed and unflagged, which is why the
/// app can't simply forbid cleartext traffic. Private and local means:
/// loopback, RFC 1918, link-local, the 100.64/10 shared range (Tailscale and
/// carrier-grade NAT), IPv6 unique-local and link-local, `localhost`,
/// single-label hosts, and the `.local`, `.lan`, `.home`, `.home.arpa`,
/// `.internal` and `.localdomain` suffixes. An unparseable URL isn't flagged.
bool sendsCredentialsInClear(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'http') return false;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  return !_isLocalHost(host);
}

bool _isLocalHost(String host) {
  if (host.contains(':')) return _isLocalV6(host);
  final v4 = _parseV4(host);
  if (v4 != null) return _isLocalV4(v4);
  if (host == 'localhost' || !host.contains('.')) return true;
  const localSuffixes = [
    '.local',
    '.lan',
    '.home',
    '.home.arpa',
    '.internal',
    '.localdomain',
  ];
  return localSuffixes.any(host.endsWith);
}

List<int>? _parseV4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return null;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((o) => o == null || o < 0 || o > 255)) return null;
  return octets.cast<int>();
}

bool _isLocalV4(List<int> ip) {
  final [a, b, _, _] = ip;
  return a == 127 ||
      a == 10 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 169 && b == 254) ||
      (a == 100 && b >= 64 && b <= 127);
}

bool _isLocalV6(String host) {
  final h = host.replaceAll('[', '').replaceAll(']', '');
  if (h == '::1') return true;
  // fc00::/7 (unique local) and fe80::/10 (link-local).
  return h.startsWith('fc') ||
      h.startsWith('fd') ||
      RegExp(r'^fe[89ab]').hasMatch(h);
}
