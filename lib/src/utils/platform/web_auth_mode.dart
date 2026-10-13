// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/enum.dart';

/// Injectable read of [kIsWeb] so tests can drive the browser branches.
final isWebProvider = Provider<bool>((ref) => kIsWeb);

/// Sign-in methods the Connection screen offers. The browser build only works
/// with UI login or no auth: Simple login needs its cookie and Basic needs
/// WebSocket headers, neither of which a cross-origin page can use.
List<AuthType> connectionAuthChoices({required bool isWeb}) => isWeb
    ? const [AuthType.none, AuthType.uiLogin]
    : AuthType.values;

/// Sign-in methods the onboarding login form offers. Same browser rule, but
/// the form only appears when the server needs a login, so no-auth is absent.
List<AuthType> onboardingAuthChoices({required bool isWeb}) => isWeb
    ? const [AuthType.uiLogin]
    : const [AuthType.basic, AuthType.simpleLogin, AuthType.uiLogin];

/// True for a Suwayomi mode the browser build cannot use.
bool isWebUnsupportedAuthMode(AuthType? mode) =>
    mode == AuthType.basic || mode == AuthType.simpleLogin;
