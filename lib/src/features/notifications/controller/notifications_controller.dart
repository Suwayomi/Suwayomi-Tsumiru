// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:workmanager/workmanager.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/custom_headers_store.dart';
import '../../auth/data/jwt_utils.dart';
import '../../offline/data/background/background_schedule.dart';
import '../../offline/data/background/background_token_record.dart';
import '../../offline/data/background/catchup_work_spec.dart';
import '../../offline/data/offline_repository.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../data/background/notification_background_client.dart';
import '../data/background/notification_background_entry.dart';
import '../data/local_notification_service.dart';
import '../data/notification_state_store.dart';
import 'notification_settings_providers.dart';

/// Bridges app state → the background worker: writes the durable config + token
/// record the headless isolate reads, and (re)schedules or cancels the periodic
/// WorkManager job. Call [sync] on launch, on settings change, and on auth
/// change so the worker always has a fresh, endpoint-bound configuration.
class NotificationsController {
  NotificationsController(this._ref);
  final Ref _ref;

  String _serverId() {
    final usePort = _ref.read(serverPortToggleProvider).ifNull();
    final port = usePort ? _ref.read(serverPortProvider) : null;
    return '${_ref.read(serverUrlProvider)}|${port ?? '-'}';
  }

  NotificationEndpoint _endpoint() => NotificationEndpoint(
    baseUrl: _ref.read(serverUrlProvider) ?? '',
    port: _ref.read(serverPortProvider),
    addPort: _ref.read(serverPortToggleProvider).ifNull(),
  );

  BackgroundTokenRecord _tokenRecord() {
    final authType = _ref.read(authTypeKeyProvider) ?? AuthType.none;
    final basicToken = _ref.read(credentialsProvider).value;
    final creds = _ref.read(authCredentialsStoreProvider).value;
    return BackgroundTokenRecord(
      gen: 0,
      authType: authType.name,
      endpoint: _serverId(),
      accessToken: creds?.uiAccessToken,
      refreshToken: creds?.uiRefreshToken,
      basicCredential: basicToken,
      simpleCookie: creds?.simpleLoginCookie,
      extraHeaders: Map<String, String>.from(
        _ref.read(customHttpHeadersProvider).value ?? const {},
      ),
    );
  }

  /// Persist config + token and reconcile the schedule with current settings.
  Future<void> sync() async {
    await withBackgroundScheduleLock(() async {
      final newChapters = _ref
          .read(notificationsNewChaptersEnabledProvider)
          .ifNull();
      final appUpdates = _ref
          .read(notificationsAppUpdatesEnabledProvider)
          .ifNull();
      final extUpdates = _ref
          .read(notificationsExtensionUpdatesEnabledProvider)
          .ifNull();
      final store = await NotificationStateStore.open();

      final appVersion = (await PackageInfo.fromPlatform()).version;
      var token = _tokenRecord();
      final saved = store.readTokenRecord();
      final controls = CatchupStateStore(_ref.read(sharedPreferencesProvider));
      final identityEpoch = controls.identityEpoch;
      if (controls.identityAuthorized &&
          store.readConfig()?.identityEpoch == controls.identityEpoch &&
          saved != null &&
          saved.endpoint == token.endpoint &&
          saved.authType == token.authType &&
          saved.authType == 'uiLogin' &&
          saved.gen > 0 &&
          saved.accessToken != null &&
          saved.refreshToken != null) {
        final savedExpiry = decodeJwtExp(saved.accessToken!);
        final currentExpiry = token.accessToken == null
            ? null
            : decodeJwtExp(token.accessToken!);
        if (savedExpiry != null &&
            (currentExpiry == null || !currentExpiry.isAfter(savedExpiry))) {
          final credentials = _ref.read(authCredentialsStoreProvider.notifier);
          final epoch = credentials.serverEpoch;
          await credentials.saveUiLoginTokens(
            accessToken: saved.accessToken!,
            refreshToken: saved.refreshToken!,
            forEpoch: epoch,
          );
          if (!controls.identityAuthorized ||
              controls.identityEpoch != identityEpoch) {
            return;
          }
          token = saved;
        }
      }
      final config = NotificationWorkerConfig(
        serverId: _serverId(),
        endpoint: _endpoint(),
        newChaptersEnabled: newChapters,
        includedCategoryIds: _ids(
          _ref.read(notificationsCategoriesIncludeProvider),
        ),
        excludedCategoryIds: _ids(
          _ref.read(notificationsCategoriesExcludeProvider),
        ),
        hideContent: _ref.read(notificationsHideContentProvider).ifNull(),
        appUpdatesEnabled: appUpdates,
        extensionUpdatesEnabled: extUpdates,
        appVersion: appVersion,
        identityEpoch: CatchupStateStore(
          _ref.read(sharedPreferencesProvider),
        ).identityEpoch,
        wifiOnly: _ref.read(notificationsWifiOnlyProvider) ?? true,
        chargingOnly: _ref.read(notificationsChargingOnlyProvider) ?? false,
        intervalHours: _ref.read(notificationsCheckIntervalHoursProvider) ?? 6,
        catalogServerId: _ref.read(offlineActiveProvider)
            ? _ref
                  .read(sharedPreferencesProvider)
                  .getString(DBKeys.offlineCatalogServerId.name)
            : null,
        verifiedAddress: _ref.read(offlineActiveProvider)
            ? _ref.read(currentServerAddressProvider)
            : null,
      );
      await store.writeTokenRecord(token);
      await store.writeConfig(config);

      // The periodic job runs when ANY check is on; if the new-chapter check went
      // off, drop its detection state.
      if (!newChapters) await store.clearState();
    });
    await reconcileBackgroundSchedule();
  }

  /// Create the channels and request the Android 13+ POST_NOTIFICATIONS
  /// permission before enabling, then reconcile the schedule.
  Future<void> requestPermissionAndSync() async {
    final service = LocalNotificationService();
    await service.init();
    await service.requestPermission();
    await sync();
  }

  /// Manual "check now" — a one-off job under its OWN unique name so it can't
  /// collide with or suppress the periodic schedule.
  Future<void> checkNow() async {
    await sync();
    await Workmanager().registerOneOffTask(
      kNewChapterCheckNowName,
      kNewChapterCheckTask,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Set<int> _ids(List<String>? raw) => {
    for (final s in raw ?? const <String>[]) int.parse(s),
  };
}

final notificationsControllerProvider = Provider<NotificationsController>(
  (ref) => NotificationsController(ref),
);
