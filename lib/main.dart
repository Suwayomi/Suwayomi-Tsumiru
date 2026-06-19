// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/constants/enum.dart';
import 'src/features/about/presentation/about/controllers/about_controller.dart';
import 'src/features/auth/data/auth_coordinator.dart';
import 'src/features/auth/data/auth_credentials_store.dart';
import 'src/features/auth/data/basic_auth_migration.dart';
import 'src/features/auth/data/secure_credentials_provider.dart';
import 'src/features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import 'src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'src/global_providers/global_providers.dart';
import 'src/sorayomi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final packageInfo = await PackageInfo.fromPlatform();
  final sharedPreferences = await SharedPreferences.getInstance();
  await initHiveForFlutter();

  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // Build a ProviderContainer so we can run migration and preload auth
  // providers before the first frame. Using UncontrolledProviderScope below
  // ensures the widget tree uses this same container instance.
  final container = ProviderContainer(
    overrides: [
      packageInfoProvider.overrideWithValue(packageInfo),
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      hiveStoreProvider.overrideWithValue(HiveStore()),
    ],
  );

  final secure = container.read(secureStorageProvider);

  // 1) Migrate legacy SharedPreferences basic-auth → secure storage.
  try {
    await migrateBasicAuthCredentials(prefs: sharedPreferences, secure: secure);
  } catch (e, st) {
    debugPrint('basic_auth migration failed: $e\n$st');
    // Non-fatal: legacy creds stay in SharedPreferences for one more launch.
  }

  // 2) Preload both auth providers BEFORE the first frame so synchronous reads
  //    (image widgets, GraphQL links) get populated state instead of
  //    AsyncLoading — which would produce tokenless requests that get cached
  //    as 401 failures by cached_network_image.
  try {
    await Future.wait([
      container.read(authCredentialsStoreProvider.future),
      container.read(credentialsProvider.future),
    ]);
  } catch (e, st) {
    debugPrint('auth preload failed, falling back to empty state: $e\n$st');
    // Both notifiers will re-attempt on first widget read. App still launches.
  }

  // 3) Eagerly instantiate the AuthCoordinator so its build() runs and
  //    sets up the proactive-refresh listener BEFORE any image request
  //    can see an expired token. Without this, the Coordinator stays
  //    lazy until something hits a 401 — which for an existing logged-in
  //    session may not happen for the entire 5-minute access-token
  //    lifetime, exactly the window we're trying to close.
  //    `read(.notifier)` constructs the notifier and runs build().
  try {
    container.read(authCoordinatorProvider.notifier);
  } catch (e, st) {
    debugPrint('auth coordinator preload failed: $e\n$st');
    // Non-fatal: reactive 401-refresh path still works on first use.
  }

  // 4) Debug-only: auto-connect + auto-login from a local --dart-define test
  //    config (see scripts/run-test.sh). No-op in release builds or when
  //    TEST_SERVER_URL isn't provided, so it never affects real users.
  try {
    await _seedTestConfig(container);
  } catch (e, st) {
    debugPrint('test-config seed failed: $e\n$st');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const Sorayomi(),
    ),
  );
}

/// Seeds server URL + auth from `--dart-define`s so test launches come up
/// already connected and logged in. Local dev convenience only — gated on
/// [kDebugMode] and the presence of `TEST_SERVER_URL`. The password is NEVER
/// stored in the repo; it comes from a gitignored launcher (scripts/run-test.sh).
Future<void> _seedTestConfig(ProviderContainer container) async {
  if (!kDebugMode) return;
  const url = String.fromEnvironment('TEST_SERVER_URL');
  if (url.isEmpty) return;
  const user = String.fromEnvironment('TEST_USER');
  const pass = String.fromEnvironment('TEST_PASS');

  container.read(serverUrlProvider.notifier).update(url);
  if (url.startsWith('https')) {
    // Reverse-proxied https servers need no extra port appended.
    container.read(serverPortToggleProvider.notifier).update(false);
  }
  container.read(authTypeKeyProvider.notifier).update(AuthType.uiLogin);
  if (user.isNotEmpty) {
    container.read(authUsernameProvider.notifier).update(user);
  }

  if (pass.isEmpty) return; // server set; user logs in manually if no password.
  await container.read(authCoordinatorProvider.notifier).loginUi(
        gqlClient: container.read(graphQlClientProvider),
        username: user,
        password: pass,
      );
}
