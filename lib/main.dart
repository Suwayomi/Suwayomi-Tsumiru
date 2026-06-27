// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:app_links/app_links.dart';
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
import 'src/features/offline/data/background/background_download_controller_shim.dart';
import 'src/features/offline/data/offline_background_downloads.dart';
import 'src/features/offline/data/offline_bootstrap.dart';
import 'src/features/offline/data/offline_download_providers.dart';
import 'src/features/offline/data/offline_repository.dart';
import 'src/features/onboarding/data/onboarding_complete.dart';
import 'src/features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import 'src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'src/features/tracking/data/tracker_repository.dart';
import 'src/features/tracking/domain/tracker_oauth_helpers.dart';
import 'src/global_providers/global_providers.dart';
import 'src/sorayomi.dart';
import 'src/utils/misc/toast/toast.dart';
import 'src/utils/platform/is_android_native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise the foreground-task plugin (Android-only; no-op elsewhere) before
  // any download service is started. Must run after the binding is ready.
  initForegroundTaskService();
  final packageInfo = await PackageInfo.fromPlatform();
  final sharedPreferences = await SharedPreferences.getInstance();
  await initHiveForFlutter();

  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // Open the on-device offline catalog. Null on web (offline disabled there);
  // failure is non-fatal — the app still launches, offline features stay off.
  final offlineStorage = await () async {
    try {
      return await initOfflineStorage();
    } catch (e, st) {
      debugPrint('offline storage init failed: $e\n$st');
      return null;
    }
  }();

  // Build a ProviderContainer so we can run migration and preload auth
  // providers before the first frame. Using UncontrolledProviderScope below
  // ensures the widget tree uses this same container instance.
  final container = ProviderContainer(
    overrides: [
      packageInfoProvider.overrideWithValue(packageInfo),
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      hiveStoreProvider.overrideWithValue(HiveStore()),
      if (offlineStorage != null) ...[
        offlineDatabaseProvider.overrideWithValue(offlineStorage.db),
        offlinePathsProvider.overrideWithValue(offlineStorage.paths),
        offlinePageStoreProvider.overrideWithValue(offlineStorage.store),
        offlineEnabledProvider.overrideWithValue(true),
      ],
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

  // 2) One-time: installs from before "Ignore Safe Area" defaulted on kept their
  //    saved `false`, so the reader's SafeArea ate the camera-cutout / notch row
  //    and the webtoon strip stopped below it. Flip it on once; the guard key
  //    means a later deliberate toggle-off by the user still sticks.
  try {
    const migratedKey = 'readerIgnoreSafeAreaDefaultOnMigrated';
    if (sharedPreferences.getBool(migratedKey) != true) {
      if (sharedPreferences.getBool('readerIgnoreSafeArea') == false) {
        await sharedPreferences.setBool('readerIgnoreSafeArea', true);
      }
      await sharedPreferences.setBool(migratedKey, true);
    }
  } catch (e, st) {
    debugPrint('readerIgnoreSafeArea migration failed: $e\n$st');
  }

  // 3) One-time: an install that already points at a real server has already
  //    "onboarded" — seed the flag so the new first-run wizard never shows for
  //    existing users. Only run when the flag is unset; treat the default
  //    loopback URL (and no URL) as not-configured.
  try {
    if (sharedPreferences.getBool('onboardingComplete') == null) {
      final url = sharedPreferences.getString('serverUrl');
      await sharedPreferences.setBool(
          'onboardingComplete', serverConfiguredForOnboarding(url));
    }
  } catch (e, st) {
    debugPrint('onboarding migration failed: $e\n$st');
  }

  // 4) Preload both auth providers BEFORE the first frame so synchronous reads
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

  // 5) Eagerly instantiate the AuthCoordinator so its build() runs and
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

  // 6) Debug-only: auto-connect + auto-login from a local --dart-define test
  //    config (see scripts/run-test.sh). No-op in release builds or when
  //    TEST_SERVER_URL isn't provided, so it never affects real users.
  try {
    await _seedTestConfig(container);
  } catch (e, st) {
    debugPrint('test-config seed failed: $e\n$st');
  }

  _setupDeepLinkListener(container);

  // 7) Sweep any chapter left mid-download by a prior crash/kill back to a
  //    clean state so it can be retried. Fire-and-forget; native only.
  if (offlineStorage != null) {
    // Push read progress made offline, re-apply keep-rules (queues anything
    // missing), then resume the download queue: chapters stranded `downloading`
    // by the last exit and previously-errored ones are retried, one at a time,
    // re-fetching only pages not already on disk. Fire-and-forget; native only.
    unawaited(Future(() async {
      await pushPendingProgress(container);
      await reconcileAllAtLaunch(container);
      if (isAndroidNative) {
        // Android: the foreground-service worker owns downloads. Register the
        // lifecycle/connectivity hooks, replay any leftover completion log into
        // drift, and restart the service if the queue is non-empty.
        final controller = container.read(backgroundDownloadControllerProvider);
        controller.register();
        await controller.replayAtLaunchAndMaybeStart();
      } else {
        await initOfflineDownloads(container);
      }
    }));
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const Sorayomi(),
    ),
  );
}

/// Sets up the AppLinks deep-link listener so that OAuth callbacks of the form
/// `tsumiru://tracker-oauth?...&state=...` are handled automatically.
///
/// Checks for an initial link (cold-start) and subscribes to the uriLinkStream
/// (warm-start). Both paths parse the tracker ID from the `state` query param,
/// call `loginOAuth`, and invalidate `trackersProvider`.
void _setupDeepLinkListener(ProviderContainer container) {
  final appLinks = AppLinks();

  Future<void> handleUri(Uri uri) async {
    if (uri.scheme != 'tsumiru' || uri.host != 'tracker-oauth') return;
    final trackerId = parseTrackerIdFromCallback(uri);
    if (trackerId == null) {
      debugPrint('tracker-oauth callback: missing/invalid trackerId in state');
      return;
    }
    try {
      await container.read(trackerRepositoryProvider).loginOAuth(
            trackerId: trackerId,
            callbackUrl: uri.toString(),
          );
      container.invalidate(trackersProvider);
    } catch (e) {
      debugPrint('tracker-oauth loginOAuth failed: $e');
      try {
        container.read(toastProvider)?.showError(e.toString());
      } catch (_) {
        // toast unavailable before widget binding
      }
    }
  }

  // Cold-start: the app was launched via a deep link.
  appLinks.getInitialLink().then((uri) {
    if (uri != null) unawaited(handleUri(uri));
  }).catchError((e) {
    debugPrint('AppLinks.getInitialLink error: $e');
  });

  // Warm-start: the app was already running and received a deep link.
  appLinks.uriLinkStream.listen(
    (uri) => unawaited(handleUri(uri)),
    onError: (e) => debugPrint('AppLinks.uriLinkStream error: $e'),
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
