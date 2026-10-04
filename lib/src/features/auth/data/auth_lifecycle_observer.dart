// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../global_providers/global_providers.dart';
import 'auth_coordinator.dart';

class AuthLifecycleObserver with WidgetsBindingObserver {
  AuthLifecycleObserver(this._ref);

  final WidgetRef _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final coord = _ref.read(authCoordinatorProvider.notifier);
    final gql = _ref.read(unauthenticatedGraphQlClientProvider);
    coord
        .refreshUiAccessTokenIfDue(gqlClient: gql, trigger: 'resume')
        .catchError((Object e) {
          debugPrint('lifecycle resume refresh failed: $e');
          return null;
        });
  }
}
