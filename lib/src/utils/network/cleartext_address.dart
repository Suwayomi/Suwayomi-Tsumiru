// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

/// Flags public HTTP URLs that expose credentials; local/private and unparseable URLs are unflagged.
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
