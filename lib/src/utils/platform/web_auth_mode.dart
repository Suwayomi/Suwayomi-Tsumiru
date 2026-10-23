// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/enum.dart';
import '../../features/offline/data/offline_server_identity_repository.dart';

final isWebProvider = Provider<bool>((ref) => kIsWeb);

/// True when [serverAddress] is on the page's own origin, so the server
/// already authenticated the browser before the app loaded.
bool isSameOriginServer({
  required String pageOrigin,
  required String serverAddress,
}) {
  final page = Uri.tryParse(pageOrigin);
  final server = Uri.tryParse(serverAddress);
  if (page == null || server == null) return false;
  if (page.host.isEmpty || server.host.isEmpty) return false;
  return page.scheme.toLowerCase() == server.scheme.toLowerCase() &&
      page.host.toLowerCase() == server.host.toLowerCase() &&
      page.port == server.port;
}

/// Served by the Suwayomi server itself: the browser is already signed in.
final webSameOriginProvider = Provider<bool>(
  (ref) =>
      ref.watch(isWebProvider) &&
      isSameOriginServer(
        pageOrigin: Uri.base.origin,
        serverAddress: ref.watch(currentServerAddressProvider),
      ),
);

List<AuthType> connectionAuthChoices({required bool isWeb}) =>
    isWeb ? const [AuthType.none, AuthType.uiLogin] : AuthType.values;

List<AuthType> onboardingAuthChoices({required bool isWeb}) => isWeb
    ? const [AuthType.uiLogin]
    : const [AuthType.basic, AuthType.simpleLogin, AuthType.uiLogin];

bool isWebUnsupportedAuthMode(AuthType? mode) =>
    mode == AuthType.basic || mode == AuthType.simpleLogin;
