// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../data/auth_coordinator.dart';

/// The one place a sign-in failure becomes words, shared by every surface that
/// signs in. Kept together so a failure can't read as "is your URL pointing at
/// the Suwayomi API?" on one screen and as a rejected password on another.
String authFailureText(BuildContext context, TestConnectionFailureKind kind) =>
    switch (kind) {
      TestConnectionFailureKind.network =>
        context.l10n.authTestConnectionFailedNetwork,
      TestConnectionFailureKind.tls => context.l10n.authTestConnectionFailedTls,
      TestConnectionFailureKind.invalidCredentials =>
        context.l10n.authTestConnectionFailedAuth,
      TestConnectionFailureKind.wrongAuthMode =>
        context.l10n.authTestConnectionFailedMode,
      TestConnectionFailureKind.unexpectedShape =>
        context.l10n.authTestConnectionFailedShape,
      TestConnectionFailureKind.insecureTransport =>
        context.l10n.authInsecureTransportWarning,
    };
