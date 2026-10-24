// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import '../../../../constants/enum.dart';

/// Strips the scheme and appends [port] only when [portToggle] is enabled.
String formatServerHost(String? url, int? port, bool portToggle) {
  var host = (url ?? '').trim();
  if (host.isEmpty) return '';
  final schemeIdx = host.indexOf('://');
  if (schemeIdx != -1) host = host.substring(schemeIdx + 3);
  if (host.endsWith('/')) host = host.substring(0, host.length - 1);
  if (portToggle && port != null) host = '$host:$port';
  return host;
}

enum ConnectionAuthStatus { signedIn, noAuth, signInNeeded }

ConnectionAuthStatus connectionAuthStatus(AuthType? authType, bool needsReauth) {
  if (needsReauth) return ConnectionAuthStatus.signInNeeded;
  if (authType == null || authType == AuthType.none) {
    return ConnectionAuthStatus.noAuth;
  }
  return ConnectionAuthStatus.signedIn;
}
