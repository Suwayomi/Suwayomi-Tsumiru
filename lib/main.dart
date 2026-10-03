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
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'src/constants/enum.dart';
import 'src/constants/timeout_constants.dart';
import 'src/features/about/presentation/about/controllers/about_controller.dart';
import 'src/features/account/data/account_bootstrap.dart';
import 'src/features/account/data/account_session_startup.dart';
import 'src/features/account/data/account_session_storage.dart';
import 'src/features/account/presentation/account_session_host.dart';
import 'src/features/auth/data/auth_coordinator.dart';
import 'src/features/auth/data/auth_credentials_store.dart';
import 'src/features/auth/data/auth_session_transition.dart';
import 'src/features/auth/data/basic_auth_migration.dart';
import 'src/features/auth/data/custom_headers_store.dart';
import 'src/features/auth/data/secure_credentials_provider.dart';
import 'src/features/library/data/badge_preference_migration.dart';
import 'src/features/notifications/data/background/notification_background_entry.dart';
import 'src/features/offline/data/account_storage_recovery_state.dart';
import 'src/features/offline/data/background/background_download_controller_shim.dart';
import 'src/features/offline/data/background/catchup_work_spec.dart';
import 'src/features/offline/data/offline_background_downloads.dart';
import 'src/features/offline/data/offline_download_coordinator.dart';
import 'src/features/offline/data/offline_repository.dart';
import 'src/features/offline/data/offline_runtime_storage.dart';
import 'src/features/offline/data/offline_server_identity_repository.dart';
import 'src/features/onboarding/data/onboarding_complete.dart';
import 'src/features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import 'src/features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'src/features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import 'src/features/settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import 'src/features/tracking/data/tracker_repository.dart';
import 'src/features/tracking/domain/tracker_oauth_helpers.dart';
import 'src/global_providers/global_providers.dart';
import 'src/sorayomi.dart';
import 'src/utils/crash/crash_log.dart';
import 'src/utils/crash/diagnostics.dart';
import 'src/utils/crash/provider_failure_logger.dart';
import 'src/utils/crash/redact_tokens.dart';
import 'src/utils/desktop/desktop_window.dart';
import 'src/utils/hive/graphql_cache_guard.dart';
import 'src/utils/misc/toast/toast.dart';
import 'src/utils/network/graphql_errors.dart';
import 'src/utils/soft_clear_image_cache.dart';
import 'src/widgets/app_error_app.dart';
import 'src/widgets/cover_cache/cover_cache.dart';

/// Absolute path of the crash-log file (native only; null on web / if setup
/// fails). The error handlers append to it synchronously.
String? _crashLogPath;

/// True once the app has painted its first frame. Distinguishes a genuine
/// startup failure (show the error screen) from a recoverable runtime async
/// error (log only; keep the app running). See [_onFatalError].
bool _appRendered = false;

/// Stock binding except the image cache survives memory-pressure signals
/// with a working set intact (see [SoftClearImageCache]) — Android sends one
/// for plain backgrounding, and the default clear-to-zero re-faded every
/// cover on return.
class _TsumiruWidgetsBinding extends WidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => SoftClearImageCache(floorBytes: 64 << 20);

  static WidgetsBinding ensureInitialized() {
    // First thing in main, so no binding exists yet; constructing a second
    // one would assert, which is the alarm we'd want if that ever lied.
    _TsumiruWidgetsBinding();
    return WidgetsBinding.instance;
  }
}

void main() {
  // Run everything inside a guarded zone so a fatal error — sync, async, or
  // framework — is caught, written to a log file, and shown as a readable
  // screen instead of a blank white window (release desktop has no console).
  runZonedGuarded<Future<void>>(_startApp, _onFatalError);
}

Future<void> _startApp() async {
  _TsumiruWidgetsBinding.ensureInitialized();
  // 100 MB default is too small even for tile-sized covers — evicted covers
  // re-shimmer on every tab switch. A cap, not an allocation.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  await _setUpCrashReporting();
  // Initialise the foreground-task plugin (Android-only; no-op elsewhere) before
  // any download service is started. Must run after the binding is ready.
  initForegroundTaskService();
  // Register the background notification scheduler's isolate entry point
  // (Android only). The periodic job itself is (re)scheduled from the launch
  // sync below once settings are available.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    Workmanager().initialize(notificationCallbackDispatcher);
  }
  final packageInfo = await PackageInfo.fromPlatform();
  _logBoot(
    'start v${packageInfo.version}+${packageInfo.buildNumber} '
    '(${defaultTargetPlatform.name})',
  );
  final sharedPreferences = await SharedPreferences.getInstance();
  // Desktop: hide the OS title bar + restore saved window size before first
  // frame. No-op on web/mobile.
  await initDesktopWindow(sharedPreferences);
  // The GraphQL cache is in-memory now; reclaim the legacy on-disk box, whose
  // unbounded growth OOM-crashed startup when Hive loaded it whole.
  final legacyBoxBytes = await deleteLegacyGraphqlCacheBox();
  if (legacyBoxBytes != null) {
    _logBoot('deleted legacy graphql cache box: $legacyBoxBytes bytes');
  }

  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  GoRouter.optionURLReflectsImperativeAPIs = true;

  final container = _createSessionContainer(packageInfo, sharedPreferences);

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
    await seedFirstRunPreferences(sharedPreferences);
  } catch (e, st) {
    debugPrint('onboarding migration failed: $e\n$st');
  }

  // 3.1) Split the legacy single endpoint into the configured remote URL and
  // the active endpoint. This must happen before the LAN resolver can replace
  // `serverUrl`, otherwise the original remote address would be lost on the
  // next launch.
  try {
    const externalKey = 'serverExternalUrl';
    if (sharedPreferences.getString(externalKey) == null) {
      final legacyUrl = sharedPreferences.getString('serverUrl');
      if (legacyUrl != null) {
        await sharedPreferences.setString(externalKey, legacyUrl);
      }
    }
  } catch (e, st) {
    debugPrint('server URL split migration failed: $e\n$st');
  }

  // 3.5) One-time: the Last-Read sort comparator was un-inverted so its
  //    ascending/descending is now ascending = oldest-read first.
  //    A user whose CURRENT sort is Last-Read and who had an explicit direction
  //    saved would otherwise see their order silently flip; flip their saved
  //    direction once to preserve their view. Only touch it when they're on
  //    Last-Read (direction is a global setting shared by every sort key), and
  //    only when a direction was explicitly saved (unset users get the new
  //    default, which already yields newest-first).
  try {
    const migratedKey = 'lastReadSortDirectionMigrated';
    if (sharedPreferences.getBool(migratedKey) != true) {
      final sortIdx = sharedPreferences.getInt('mangaSort');
      // mangaSort default is Last-Read, so an unset value means Last-Read too.
      final onLastRead = sortIdx == null || sortIdx == MangaSort.lastRead.index;
      final savedDir = sharedPreferences.getBool('mangaSortDirection');
      if (onLastRead && savedDir != null) {
        await sharedPreferences.setBool('mangaSortDirection', !savedDir);
      }
      await sharedPreferences.setBool(migratedKey, true);
    }
  } catch (e, st) {
    debugPrint('lastRead sort direction migration failed: $e\n$st');
  }

  // 3.6) One-time: the old request-timeout model was broken twice over (a
  //    hidden 5s graphql-layer cap the setting never reached, and retries
  //    subdivided into delay-sized attempts). Any saved value was tuned
  //    against that broken behavior, so move EVERY install to the new model:
  //    30s timeout, auto-retry on. Deliberate full override, per Aaron.
  try {
    const migratedKey = 'requestTimeout30sMigrated';
    if (sharedPreferences.getBool(migratedKey) != true) {
      await sharedPreferences.setInt(
        'serverRequestTimeout',
        TimeoutConstants.requestTimeoutDefaultMs,
      );
      await sharedPreferences.setBool('autoRefreshOnTimeout', true);
      await sharedPreferences.setBool(migratedKey, true);
    }
  } catch (e, st) {
    debugPrint('request timeout migration failed: $e\n$st');
  }

  // 3.7) One-time: the badge revamp replaced three preference keys. Seed the
  //    new ones from the old so an upgrade keeps the badges the user picked.
  try {
    await migrateBadgePreferences(sharedPreferences);
  } catch (e, st) {
    debugPrint('badge preference migration failed: $e\n$st');
  }

  // 4) Preload both auth providers (plus the custom-header store) BEFORE the
  //    first frame so synchronous reads (image widgets, GraphQL links) get
  //    populated state instead of AsyncLoading — which would produce tokenless
  //    requests that get cached as 401 failures by cached_network_image.
  try {
    await Future.wait([
      container.read(authCredentialsStoreProvider.future),
      container.read(credentialsProvider.future),
      container.read(customHttpHeadersProvider.future),
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

  await CatchupStateStore(sharedPreferences).setIdentityAuthorized(false);
  try {
    await restoreAccountSession(container);
    _logBoot(
      container.read(offlineEnabledProvider)
          ? 'offline storage ready'
          : 'offline off',
    );
  } catch (error, stack) {
    debugPrint('account storage initialization failed: $error\n$stack');
    _logBoot(
      'account storage initialization failed: ${redactTokens('$error')}',
    );
  }
  container.read(authCredentialsStoreProvider.notifier).activateSession();
  container.read(serverEndpointResolverProvider.notifier);
  var activeContainer = container;
  var startup = AccountSessionStartup(container)..start();
  _setupDeepLinkListener(() => activeContainer);

  Future<ProviderContainer> restartSession(ProviderContainer previous) async {
    startup.dispose();
    previous.read(offlineDownloadCoordinatorProvider)?.pause();
    await previous.read(backgroundDownloadControllerProvider).detachStorage();
    await OfflineDownloadCoordinator.stopAll();
    final oldStorage = previous.read(offlineRuntimeStorageProvider.notifier);
    await oldStorage.drain();
    await previous.read(authCredentialsStoreProvider.notifier).retire();
    final next = _createSessionContainer(
      packageInfo,
      sharedPreferences,
      coverCache: previous.read(coverCacheManagerProvider),
    );
    OfflineStorage? transferred;
    AccountSessionStartup? nextStartup;
    try {
      await Future.wait([
        next.read(authCredentialsStoreProvider.future),
        next.read(credentialsProvider.future),
        next.read(customHttpHeadersProvider.future),
      ]);
      await CatchupStateStore(sharedPreferences).setIdentityAuthorized(false);
      next
          .read(accountStorageRecoveryProvider.notifier)
          .update(previous.read(accountStorageRecoveryProvider));
      transferred = oldStorage.take();
      await next
          .read(offlineRuntimeStorageProvider.notifier)
          .replace(drain: () async {}, open: () async => transferred);
      next.read(authCredentialsStoreProvider.notifier).activateSession();
      next.read(authCoordinatorProvider.notifier);
      next.read(serverEndpointResolverProvider.notifier);
      nextStartup = AccountSessionStartup(next);
      nextStartup.start();
      startup = nextStartup;
      activeContainer = next;
      return next;
    } catch (_) {
      nextStartup?.dispose();
      try {
        final runtime = next.read(offlineRuntimeStorageProvider.notifier);
        if (next.read(offlineRuntimeStorageProvider) == null) {
          await transferred?.db.close();
        } else {
          await runtime.replace(
            drain: runtime.whenIdle,
            open: () async => null,
          );
        }
      } finally {
        next.dispose();
      }
      rethrow;
    }
  }

  Future<void> retainSession(ProviderContainer retained) async {
    startup.dispose();
    retained.read(authCredentialsStoreProvider.notifier).activateSession();
    final current = retained
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    await retained.read(offlineRuntimeStorageProvider.notifier).whenIdle();
    if (!current() || activeContainer != retained) return;
    retained.invalidate(backgroundDownloadControllerProvider);
    startup = AccountSessionStartup(retained);
    await startup.start();
  }

  _logBoot('runApp');
  runApp(
    AccountSessionHost(
      initialContainer: container,
      restart: restartSession,
      onRetained: retainSession,
      sessionKey: (session) {
        final credentials = session.read(authCredentialsStoreProvider).value;
        return (
          session.read(authTypeKeyProvider),
          session.read(currentServerAddressProvider),
          session.read(credentialsProvider).value,
          credentials?.accountBinding,
          credentials?.uiAccessToken,
          credentials?.uiRefreshToken,
          credentials?.simpleLoginCookie,
          session.read(offlineRuntimeStorageProvider),
        );
      },
      builder: (changing) => Sorayomi(sessionChanging: changing),
      loading: const AccountSessionLoading(),
      errorBuilder: (error) =>
          AppErrorApp(message: redactTokens('$error'), logPath: _crashLogPath),
    ),
  );
  // Mark the app as up once it has painted a frame. After this, a stray
  // uncaught async error is recoverable and must NOT replace the whole UI with
  // the fatal screen (see [_onFatalError]).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _appRendered = true;
    _logBoot('first frame');
  });
}

ProviderContainer _createSessionContainer(
  PackageInfo packageInfo,
  SharedPreferences preferences, {
  CacheManager? coverCache,
}) => ProviderContainer(
  observers: [ProviderFailureLogger()],
  retry: (retryCount, error) => isConnectionError(error)
      ? null
      : ProviderContainer.defaultRetry(retryCount, error),
  overrides: [
    packageInfoProvider.overrideWithValue(packageInfo),
    sharedPreferencesProvider.overrideWithValue(preferences),
    if (coverCache != null)
      coverCacheManagerProvider.overrideWithValue(coverCache),
    authSessionTransitionProvider.overrideWith(
      (ref) => ref.read(accountSessionStorageProvider),
    ),
  ],
);

/// Startup breadcrumbs in the crash log: a boot that dies pre-frame leaves the
/// last completed stage next to the error, instead of a bare stack with no
/// context (the startup-OOM class was undiagnosable without this).
void _logBoot(String stage) {
  writeCrashLog(
    _crashLogPath,
    '[${DateTime.now().toIso8601String()}] boot: $stage\n',
  );
}

/// Install the framework + async error handlers and resolve the crash-log file.
/// Each handler is best-effort and never throws, so crash reporting can't itself
/// crash startup.
Future<void> _setUpCrashReporting() async {
  _crashLogPath = await initCrashLog();
  setDiagnosticSink((line) => writeCrashLog(_crashLogPath, line));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logCrash(details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    _logCrash(error, stack);
    return true;
  };
  ErrorWidget.builder = (details) => AppErrorApp(
    message: redactTokens(details.exceptionAsString()),
    logPath: _crashLogPath,
  );
}

void _logCrash(Object error, StackTrace? stack) {
  // Include the runtime type — some exceptions (e.g. wrapped GraphQL ones) have
  // an empty toString(), which would otherwise log a blank line.
  final body = redactTokens('${error.runtimeType}: $error\n$stack');
  debugPrint('Tsumiru error: $body');
  writeCrashLog(
    _crashLogPath,
    '[${DateTime.now().toIso8601String()}] $body\n\n',
  );
}

void _onFatalError(Object error, StackTrace stack) {
  _logCrash(error, stack);
  // Only a failure BEFORE the first frame is truly fatal (it would otherwise
  // leave a blank white window) — show the error screen then. Once the app has
  // painted, a stray uncaught async error (e.g. a failed network call in a
  // button handler) is recoverable: it's logged, but it must not replace the
  // running app with a "couldn't start" screen.
  if (_appRendered) return;
  try {
    runApp(
      AppErrorApp(
        message: redactTokens(error.toString()),
        logPath: _crashLogPath,
      ),
    );
  } catch (_) {}
}

/// Sets up the AppLinks deep-link listener so that OAuth callbacks of the form
/// `tsumiru://tracker-oauth?...&state=...` are handled automatically.
///
/// Checks for an initial link (cold-start) and subscribes to the uriLinkStream
/// (warm-start). Both paths parse the tracker ID from the `state` query param,
/// call `loginOAuth`, and invalidate `trackersProvider`.
void _setupDeepLinkListener(ProviderContainer Function() currentContainer) {
  final appLinks = AppLinks();

  Future<void> handleUri(Uri uri) async {
    if (uri.scheme != 'tsumiru' || uri.host != 'tracker-oauth') return;
    final trackerId = parseTrackerIdFromCallback(uri);
    if (trackerId == null) {
      debugPrint('tracker-oauth callback: missing/invalid trackerId in state');
      return;
    }
    final container = currentContainer();
    final current = container
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    if (!current()) return;
    try {
      await container
          .read(trackerRepositoryProvider)
          .loginOAuth(trackerId: trackerId, callbackUrl: uri.toString());
      if (!current()) return;
      container.invalidate(trackersProvider);
    } catch (e) {
      if (!current()) return;
      debugPrint('tracker-oauth loginOAuth failed: $e');
      try {
        container.read(toastProvider)?.showError(e.toString());
      } catch (_) {
        // toast unavailable before widget binding
      }
    }
  }

  // Cold-start: the app was launched via a deep link.
  appLinks
      .getInitialLink()
      .then((uri) {
        if (uri != null) unawaited(handleUri(uri));
      })
      .catchError((e) {
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

  await container.read(serverExternalUrlProvider.notifier).update(url);
  if (url.startsWith('https')) {
    // Reverse-proxied https servers need no extra port appended.
    await container.read(serverPortToggleProvider.notifier).update(false);
  }
  container.read(authTypeKeyProvider.notifier).update(AuthType.uiLogin);
  if (user.isNotEmpty) {
    container.read(authUsernameProvider.notifier).update(user);
  }

  if (pass.isEmpty) return; // server set; user logs in manually if no password.
  await container.read(backgroundDownloadControllerProvider).changeIdentity(
    () async {
      await container
          .read(authCoordinatorProvider.notifier)
          .loginUi(
            gqlClient: container.read(unauthenticatedGraphQlClientProvider),
            username: user,
            password: pass,
          );
    },
  );
}
