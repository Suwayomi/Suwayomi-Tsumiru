// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:workmanager/workmanager.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../offline/data/background/background_token_record.dart';
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
    );
  }

  /// Persist config + token and reconcile the schedule with current settings.
  Future<void> sync() async {
    final newChapters =
        _ref.read(notificationsNewChaptersEnabledProvider).ifNull();
    final appUpdates =
        _ref.read(notificationsAppUpdatesEnabledProvider).ifNull();
    final extUpdates =
        _ref.read(notificationsExtensionUpdatesEnabledProvider).ifNull();
    final store = await NotificationStateStore.open();

    await store.writeTokenRecord(_tokenRecord());
    final config = NotificationWorkerConfig(
      serverId: _serverId(),
      endpoint: _endpoint(),
      newChaptersEnabled: newChapters,
      includedCategoryIds: _ids(_ref.read(notificationsCategoriesIncludeProvider)),
      excludedCategoryIds: _ids(_ref.read(notificationsCategoriesExcludeProvider)),
      hideContent: _ref.read(notificationsHideContentProvider).ifNull(),
      appUpdatesEnabled: appUpdates,
      extensionUpdatesEnabled: extUpdates,
      appVersion: (await PackageInfo.fromPlatform()).version,
    );
    await store.writeConfig(config);

    // The periodic job runs when ANY check is on; if the new-chapter check went
    // off, drop its detection state.
    if (!newChapters) await store.clearState();
    if (!config.anyEnabled) {
      await Workmanager().cancelByUniqueName(kNewChapterPeriodicName);
      return;
    }
    await _schedule();
  }

  Future<void> _schedule() async {
    final hours = _ref.read(notificationsCheckIntervalHoursProvider) ?? 6;
    final wifiOnly = _ref.read(notificationsWifiOnlyProvider).ifNull(true);
    final charging = _ref.read(notificationsChargingOnlyProvider).ifNull();
    await Workmanager().registerPeriodicTask(
      kNewChapterPeriodicName,
      kNewChapterCheckTask,
      frequency: Duration(hours: hours < 1 ? 1 : hours),
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        requiresCharging: charging,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
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

  Set<int> _ids(List<String>? raw) =>
      {for (final s in raw ?? const <String>[]) int.parse(s)};
}

final notificationsControllerProvider = Provider<NotificationsController>(
  (ref) => NotificationsController(ref),
);
