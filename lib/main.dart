// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus_linux_portal/connectivity_plus_linux_portal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'src/constants/brand_icons.dart';
import 'src/constants/enum.dart';
import 'src/constants/inter_license.dart';
import 'src/constants/timeout_constants.dart';
import 'src/features/about/data/macos_app_updater.dart';
import 'src/features/about/presentation/about/controllers/about_controller.dart';
import 'src/features/account/data/account_bootstrap.dart';
import 'src/features/account/data/account_session_startup.dart';
import 'src/features/account/data/account_session_storage.dart';
import 'src/features/account/presentation/account_session_host.dart';
import 'src/features/auth/data/auth_coordinator.dart';
import 'src/features/auth/data/auth_credentials_store.dart';
import 'src/features/auth/data/auth_recovery_target.dart';
import 'src/features/auth/data/auth_session_transition.dart';
import 'src/features/auth/data/auth_state.dart';
import 'src/features/auth/data/basic_auth_migration.dart';
import 'src/features/auth/data/custom_headers_store.dart';
import 'src/features/auth/data/secure_credentials_provider.dart';
import 'src/features/library/data/badge_preference_migration.dart';
import 'src/features/notifications/data/background/notification_background_entry.dart';
import 'src/features/offline/data/account_storage_recovery_state.dart';
import 'src/features/offline/data/background/background_download_controller_shim.dart';
import 'src/features/offline/data/background/catchup_work_spec.dart';
import 'src/features/offline/data/background/record_seal.dart';
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
import 'src/features/tracking/data/native_tracker_oauth.dart';
import 'src/global_providers/global_providers.dart';
import 'src/routes/router_config.dart';
import 'src/tsumiru_app.dart';
import 'src/utils/crash/crash_log.dart';
import 'src/utils/crash/diagnostics.dart';
import 'src/utils/crash/provider_failure_logger.dart';
import 'src/utils/crash/redact_tokens.dart';
import 'src/utils/desktop/desktop_window.dart';
import 'src/utils/extensions/custom_extensions.dart';
import 'src/utils/hive/graphql_cache_guard.dart';
import 'src/utils/misc/toast/toast.dart';
import 'src/utils/network/graphql_errors.dart';
import 'src/utils/platform/is_flatpak.dart';
import 'src/utils/soft_clear_image_cache.dart';
import 'src/widgets/app_error_app.dart';
import 'src/widgets/cover_cache/cover_cache.dart';

// Native crash-log path; null on web or initialization failure.
String? _crashLogPath;

bool _appRendered = false;

// Android sends memory-pressure signals on backgrounding; retain a working set of covers.
class _TsumiruWidgetsBinding extends WidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => SoftClearImageCache(floorBytes: 64 << 20);

  static WidgetsBinding ensureInitialized() {
    // Must be the first binding created; a second binding construction asserts.
    _TsumiruWidgetsBinding();
    return WidgetsBinding.instance;
  }
}

void main() {
  runZonedGuarded<Future<void>>(_startApp, _onFatalError);
}

Future<void> _startApp() async {
  _TsumiruWidgetsBinding.ensureInitialized();
  if (kIsWeb) {
    await BrowserContextMenu.disableContextMenu();
  }
  // 256 MiB is a cache cap, not an allocation, and retains covers across tab switches.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  registerBrandIconsLicense();
  registerInterLicense();
  await _setUpCrashReporting();
  // Initialize after the binding and before starting any download service.
  initForegroundTaskService();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    Workmanager().initialize(notificationCallbackDispatcher);
  }
  if (isFlatpak) {
    ConnectivityPlusLinuxPortalPlugin.registerWith();
  }
  final packageInfo = await PackageInfo.fromPlatform();
  _logBoot(
    'start v${packageInfo.version}+${packageInfo.buildNumber} '
    '(${defaultTargetPlatform.name})',
  );
  final sharedPreferences = await SharedPreferences.getInstance();
  // Restore the desktop window before the first frame.
  await initDesktopWindow(sharedPreferences);
  final legacyBoxBytes = await deleteLegacyGraphqlCacheBox();
  if (legacyBoxBytes != null) {
    _logBoot('deleted legacy graphql cache box: $legacyBoxBytes bytes');
  }

  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // One app-lifetime updater: the native Sparkle controller is a process-wide
  // singleton, so every session container shares this instance instead of
  // constructing a fresh (unavailable) one per restart.
  final macOSUpdater = MacOSAppUpdater();
  final container = _createSessionContainer(
    packageInfo,
    sharedPreferences,
    macOSUpdater: macOSUpdater,
  );

  // Start the macOS updater before any update check; failures keep GitHub fallback.
  try {
    await macOSUpdater.initialize();
  } catch (e, st) {
    debugPrint('macOS updater init failed: $e\n$st');
  }

  final secure = container.read(secureStorageProvider);

  // Load the seal key before any background credential reads or writes.
  if (!await RecordSeal.load(secure, create: true)) {
    _logBoot('background credentials key unavailable');
  }

  try {
    await migrateBasicAuthCredentials(prefs: sharedPreferences, secure: secure);
  } catch (e, st) {
    debugPrint('basic_auth migration failed: $e\n$st');
  }

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

  try {
    const migratedKey = 'updatesGroupingCollapsedMigrated';
    if (sharedPreferences.getBool(migratedKey) != true) {
      if (sharedPreferences.getInt('updatesGroupingMode') ==
          UpdatesGroupingMode.disabled.index) {
        await sharedPreferences.setInt(
          'updatesGroupingMode',
          UpdatesGroupingMode.collapsed.index,
        );
      }
      await sharedPreferences.setBool(migratedKey, true);
    }
  } catch (e, st) {
    debugPrint('updatesGrouping migration failed: $e\n$st');
  }

  try {
    await seedFirstRunPreferences(sharedPreferences);
  } catch (e, st) {
    debugPrint('onboarding migration failed: $e\n$st');
  }

  // Preserve the remote URL before the LAN resolver can replace serverUrl.
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

  try {
    const migratedKey = 'lastReadSortDirectionMigrated';
    if (sharedPreferences.getBool(migratedKey) != true) {
      final sortIdx = sharedPreferences.getInt('mangaSort');
      // An unset mangaSort defaults to Last-Read.
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

  try {
    await migrateBadgePreferences(sharedPreferences);
  } catch (e, st) {
    debugPrint('badge preference migration failed: $e\n$st');
  }

  // Preload auth before image requests can cache tokenless 401s; sequential reads avoid repeated keychain prompts.
  try {
    await container.read(authCredentialsStoreProvider.future);
    await container.read(credentialsProvider.future);
    await container.read(customHttpHeadersProvider.future);
  } catch (e, st) {
    debugPrint('auth preload failed, falling back to empty state: $e\n$st');
  }

  // Start proactive auth refresh before any image request can use an expired token.
  try {
    container.read(authCoordinatorProvider.notifier);
  } catch (e, st) {
    debugPrint('auth coordinator preload failed: $e\n$st');
  }

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
      macOSUpdater: previous.read(macOSAppUpdaterProvider),
    );
    OfflineStorage? transferred;
    AccountSessionStartup? nextStartup;
    try {
      await Future.wait([
        next.read(authCredentialsStoreProvider.future),
        next.read(credentialsProvider.future),
        next.read(customHttpHeadersProvider.future),
      ]);
      next
          .read(authRecoveryTargetProvider.notifier)
          .set(previous.read(authRecoveryTargetProvider));
      next
          .read(needsReauthProvider.notifier)
          .set(previous.read(needsReauthProvider));
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
      builder: (changing) => TsumiruApp(sessionChanging: changing),
      loading: const AccountSessionLoading(),
      errorBuilder: (error) =>
          AppErrorApp(message: redactTokens('$error'), logPath: _crashLogPath),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _appRendered = true;
    _logBoot('first frame');
  });
}

ProviderContainer _createSessionContainer(
  PackageInfo packageInfo,
  SharedPreferences preferences, {
  CacheManager? coverCache,
  required MacOSAppUpdater macOSUpdater,
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
    macOSAppUpdaterProvider.overrideWithValue(macOSUpdater),
    authSessionTransitionProvider.overrideWith(
      (ref) => ref.read(accountSessionStorageProvider),
    ),
  ],
);

/// The production session factory, exposed for the restart regression test.
@visibleForTesting
ProviderContainer createSessionContainerForTest({
  required PackageInfo packageInfo,
  required SharedPreferences preferences,
  CacheManager? coverCache,
  required MacOSAppUpdater macOSUpdater,
}) => _createSessionContainer(
  packageInfo,
  preferences,
  coverCache: coverCache,
  macOSUpdater: macOSUpdater,
);

void _logBoot(String stage) {
  writeCrashLog(
    _crashLogPath,
    '[${DateTime.now().toIso8601String()}] boot: $stage\n',
  );
}

// Error handlers must never throw while reporting a startup failure.
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
  // Some exceptions have empty toString(); retain their runtime type.
  final body = redactTokens('${error.runtimeType}: $error\n$stack');
  debugPrint('Tsumiru error: $body');
  writeCrashLog(
    _crashLogPath,
    '[${DateTime.now().toIso8601String()}] $body\n\n',
  );
}

void _onFatalError(Object error, StackTrace stack) {
  _logCrash(error, stack);
  // After the first frame, async errors must not replace the running app with a startup error screen.
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

void _setupDeepLinkListener(ProviderContainer Function() currentContainer) {
  final appLinks = AppLinks();

  Future<void> handleUri(Uri uri) async {
    if (uri.scheme != 'tsumiru' || uri.host != 'tracker-oauth') return;
    final container = currentContainer();
    final current = container.read(authCredentialsStoreProvider.notifier).captureSession();
    if (!current()) return;
    try {
      final toast = container.read(toastProvider);
      final outcome = await container.read(nativeTrackerOAuthProvider).handleCallback(uri);
      if (!current()) return;
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      if (outcome == TrackerOAuthOutcome.rejected) {
        toast?.showError(context.l10n.trackerOAuthLinkInvalid);
      } else if (outcome == TrackerOAuthOutcome.failed) {
        toast?.showError(context.l10n.errorSomethingWentWrong);
      }
    } catch (_) {
      debugPrint('Tracker sign-in callback could not be processed');
    }
  }

  appLinks
      .getInitialLink()
      .then((uri) {
        if (uri != null) unawaited(handleUri(uri));
      })
      .catchError((e) {
        debugPrint('AppLinks initial link could not be read');
      });

  appLinks.uriLinkStream.listen(
    (uri) => unawaited(handleUri(uri)),
    onError: (_) => debugPrint('AppLinks link stream failed'),
  );
}

Future<void> _seedTestConfig(ProviderContainer container) async {
  if (!kDebugMode) return;
  const url = String.fromEnvironment('TEST_SERVER_URL');
  if (url.isEmpty) return;
  const user = String.fromEnvironment('TEST_USER');
  const pass = String.fromEnvironment('TEST_PASS');

  await container.read(serverExternalUrlProvider.notifier).update(url);
  if (url.startsWith('https')) {
    // Reverse-proxied HTTPS servers need no additional port.
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
            serverBaseUrl: url,
          );
    },
  );
}
