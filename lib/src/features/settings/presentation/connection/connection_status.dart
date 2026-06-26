// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../constants/enum.dart';

/// Renders the server address shown on the More page's Connection tile,
/// e.g. `myserver.local:4567`. Scheme is stripped; the port is appended
/// only when the user has the port toggle enabled.
String formatServerHost(String? url, int? port, bool portToggle) {
  var host = (url ?? '').trim();
  if (host.isEmpty) return '';
  final schemeIdx = host.indexOf('://');
  if (schemeIdx != -1) host = host.substring(schemeIdx + 3);
  if (host.endsWith('/')) host = host.substring(0, host.length - 1);
  if (portToggle && port != null) host = '$host:$port';
  return host;
}

/// The auth state surfaced on the Connection tile subtitle.
enum ConnectionAuthStatus { signedIn, noAuth, signInNeeded }

/// `signInNeeded` takes priority so a broken/expired session is visible on
/// More even while an auth type is still configured.
ConnectionAuthStatus connectionAuthStatus(AuthType? authType, bool needsReauth) {
  if (needsReauth) return ConnectionAuthStatus.signInNeeded;
  if (authType == null || authType == AuthType.none) {
    return ConnectionAuthStatus.noAuth;
  }
  return ConnectionAuthStatus.signedIn;
}
