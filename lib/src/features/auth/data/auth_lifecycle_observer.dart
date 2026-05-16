// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../global_providers/global_providers.dart';
import 'auth_coordinator.dart';

/// On app-resume (`AppLifecycleState.resumed`), speculatively refresh
/// the ui_login access token if it's about to expire.
///
/// Dart `Timer` does NOT fire while the Android process is suspended /
/// in Doze. The AuthCoordinator's proactive Timer would otherwise fire
/// LATE on resume — after the reader has already requested several
/// image tiles with a stale token. This observer covers the gap by
/// running a refresh-if-due before reader prefetch resumes.
///
/// No-op when:
///   - auth mode is not ui_login (gated by `refreshUiAccessTokenIfDue`)
///   - access token is more than `proactiveRefreshLead` from expiry
///   - already refreshed (single-flight skips duplicates)
class AuthLifecycleObserver with WidgetsBindingObserver {
  AuthLifecycleObserver(this._ref);

  final WidgetRef _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final coord = _ref.read(authCoordinatorProvider.notifier);
    final gql = _ref.read(graphQlClientProvider);
    // Fire and forget — return value is unused; refresh outcome is
    // observed via AuthCredentialsStore mutation.
    coord.refreshUiAccessTokenIfDue(gqlClient: gql).catchError((Object e) {
      debugPrint('lifecycle resume refresh failed: $e');
      return null;
    });
  }
}
