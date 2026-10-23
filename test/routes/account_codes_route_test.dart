// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Invite codes open as a typed route under Manage users, so the desktop top
// bar never walks past a plain MaterialPageRoute (see desktop_top_bar.dart).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/about/data/about_repository.dart';
import 'package:tsumiru/src/features/about/presentation/about/controllers/about_controller.dart';
import 'package:tsumiru/src/features/account/data/account_providers.dart';
import 'package:tsumiru/src/features/account/data/account_repository.dart';
import 'package:tsumiru/src/features/account/presentation/account_codes_screen.dart';
import 'package:tsumiru/src/features/browse_center/presentation/extension/controller/extension_update_badge.dart';
import 'package:tsumiru/src/features/offline/data/offline_nav_status.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/routes/router_config.dart';
import 'package:tsumiru/src/utils/misc/toast/toast.dart';
import 'package:tsumiru/src/utils/motion/reduce_motion.dart';
import 'package:tsumiru/src/utils/platform/platform_runtime.dart';

import '../src/features/account/account_administration_test.dart'
    show AdminLink, adminAccess;

void main() {
  testWidgets('invite codes resolve as a routed page under Manage users', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    debugDesktopPlatformOverride = true;
    addTearDown(() => debugDesktopPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/more/account/users/codes',
      navigatorKey: rootNavigatorKey,
      routes: $appRoutes,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          toastProvider.overrideWithValue(null),
          startupWebRevisionProvider.overrideWith(
            (ref) => Completer<String?>().future,
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          packageInfoProvider.overrideWithValue(
            PackageInfo(
              appName: 'Tsumiru',
              packageName: 'test',
              version: '1',
              buildNumber: '1',
            ),
          ),
          offlineEnabledProvider.overrideWithValue(false),
          downloadsPausedBadgeProvider.overrideWith((ref) => false),
          extensionUpdateBadgeCountProvider.overrideWith((ref) async => 0),
          authTypeKeyProvider.overrideWithValue(AuthType.none),
          settledAccountAccessProvider.overrideWithValue(
            adminAccess(admin: true),
          ),
          accountRepositoryProvider.overrideWithValue(
            AccountRepository(
              GraphQLClient(link: AdminLink(), cache: GraphQLCache()),
              access: () => adminAccess(admin: true),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => ReduceMotionScope(child: child!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(router.state.matchedLocation, '/more/account/users/codes');
    expect(find.byType(AccountCodesScreen), findsOneWidget);
  });
}
