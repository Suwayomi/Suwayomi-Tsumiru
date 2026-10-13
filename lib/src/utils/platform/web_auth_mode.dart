// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/enum.dart';

final isWebProvider = Provider<bool>((ref) => kIsWeb);

List<AuthType> connectionAuthChoices({required bool isWeb}) =>
    isWeb ? const [AuthType.none, AuthType.uiLogin] : AuthType.values;

List<AuthType> onboardingAuthChoices({required bool isWeb}) => isWeb
    ? const [AuthType.uiLogin]
    : const [AuthType.basic, AuthType.simpleLogin, AuthType.uiLogin];

bool isWebUnsupportedAuthMode(AuthType? mode) =>
    mode == AuthType.basic || mode == AuthType.simpleLogin;
