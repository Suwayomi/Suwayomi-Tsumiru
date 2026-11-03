// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../utils/webui_meta/webui_meta_repository.dart';
import '../../account/data/account_permission.dart';

typedef ServerUpdateAlertSettings = ({
  bool informVersionUpdated,
  bool informAvailableUpdate,
  bool webUIInformVersionUpdated,
  bool webUIInformAvailableUpdate,
  Map<String, String> metas,
});

bool _decodeAlertFlag(Map<String, String> metas, String key) {
  final raw = readWebUiValue(metas, key);
  if (raw == null) return true;
  return decodeWebUiBool(raw);
}

class ServerUpdateAlertsRepository {
  const ServerUpdateAlertsRepository(this.client, {required this.permissions});

  final GraphQLClient client;
  final AccountPermissionGuard permissions;

  Future<ServerUpdateAlertSettings?> settings() async {
    final metas = await WebUiMetaRepository(client).readGlobalMetas();
    return (
      informVersionUpdated: _decodeAlertFlag(
        metas,
        'serverInformVersionUpdated',
      ),
      informAvailableUpdate: _decodeAlertFlag(
        metas,
        'serverInformAvailableUpdate',
      ),
      webUIInformVersionUpdated: _decodeAlertFlag(
        metas,
        'webUIInformVersionUpdated',
      ),
      webUIInformAvailableUpdate: _decodeAlertFlag(
        metas,
        'webUIInformAvailableUpdate',
      ),
      metas: metas,
    );
  }

  Future<void> write(
    String key,
    bool value,
    Map<String, String> existingMetas,
  ) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => WebUiMetaRepository(
      client,
    ).writeGlobalValue(key, encodeWebUiBool(value), existingMetas),
  );
}

final serverUpdateAlertsRepositoryProvider =
    Provider<ServerUpdateAlertsRepository>(
      (ref) => ServerUpdateAlertsRepository(
        ref.watch(graphQlClientProvider),
        permissions: ref.watch(accountPermissionGuardProvider),
      ),
    );

final serverUpdateAlertSettingsProvider =
    FutureProvider.autoDispose<ServerUpdateAlertSettings?>(
      (ref) => ref.watch(serverUpdateAlertsRepositoryProvider).settings(),
    );

({bool showUpdatedNotice, bool storeVersion})
decideServerUpdateAlerts({
  required String currentVersion,
  required String? lastSeenVersion,
  required bool informVersionUpdated,
}) {
  const none = (
    showUpdatedNotice: false,
    storeVersion: false,
  );
  if (currentVersion.isBlank) return none;
  return (
    showUpdatedNotice:
        !lastSeenVersion.isBlank &&
        lastSeenVersion != currentVersion &&
        informVersionUpdated,
    storeVersion: lastSeenVersion.isBlank || lastSeenVersion != currentVersion,
  );
}

const updateCheckInterval = Duration(hours: 1);

bool shouldShowUpdate({
  required String version,
  required String? ignoredVersion,
  required int closedTimestamp,
  required int now,
}) => version != ignoredVersion &&
    now - closedTimestamp >= updateCheckInterval.inMilliseconds;

class UpdateReminderStore {
  const UpdateReminderStore(this.preferences, this.key);

  final SharedPreferences preferences;
  final String key;

  String _key(String suffix) => 'UpdateChecker::$key::$suffix';

  int get nextCheck =>
      (preferences.getInt(_key('lastUpdateCheck')) ?? 0) +
      updateCheckInterval.inMilliseconds;

  int get reminderEnds =>
      (preferences.getInt(_key('closeTimestamp')) ?? 0) +
      updateCheckInterval.inMilliseconds;

  bool show(String version) => shouldShowUpdate(
    version: version,
    ignoredVersion: preferences.getString(_key('ignoreUpdate')),
    closedTimestamp: preferences.getInt(_key('closeTimestamp')) ?? 0,
    now: DateTime.now().millisecondsSinceEpoch,
  );

  Future<void> checked() => preferences.setInt(
    _key('lastUpdateCheck'), DateTime.now().millisecondsSinceEpoch,
  );

  Future<void> remindLater() => preferences.setInt(
    _key('closeTimestamp'), DateTime.now().millisecondsSinceEpoch,
  );

  Future<void> ignore(String version) =>
      preferences.setString(_key('ignoreUpdate'), version);
}
