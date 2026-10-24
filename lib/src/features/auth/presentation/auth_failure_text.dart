// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../data/auth_coordinator.dart';

String authFailureText(BuildContext context, TestConnectionFailureKind kind) =>
    switch (kind) {
      TestConnectionFailureKind.browserSession =>
        context.l10n.authBrowserSessionUnverified,
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
      TestConnectionFailureKind.webUnsupportedAuthMode =>
        context.l10n.webUnsupportedAuthMode,
    };
