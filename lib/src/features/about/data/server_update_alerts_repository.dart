// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/webui_meta/webui_meta_codec.dart';
import '../../../utils/webui_meta/webui_meta_repository.dart';
import '../../account/data/account_permission.dart';

/// WebUI's two server-update switches, stored as global `"true"`/`"false"`
/// meta under the default profile. Absent keys mean on, matching WebUI's
/// `SERVER_SETTINGS_METADATA_DEFAULT`.
class ServerUpdateAlertSettings {
  const ServerUpdateAlertSettings({
    required this.informVersionUpdated,
    required this.informAvailableUpdate,
    required this.metas,
  });

  final bool informVersionUpdated;
  final bool informAvailableUpdate;

  /// The fetched global metas, kept for follow-up writes.
  final Map<String, String> metas;
}

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
    return ServerUpdateAlertSettings(
      informVersionUpdated: _decodeAlertFlag(
        metas,
        'serverInformVersionUpdated',
      ),
      informAvailableUpdate: _decodeAlertFlag(
        metas,
        'serverInformAvailableUpdate',
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

/// Pure launch triggers, mirroring WebUI's `ServerUpdateChecker`: the first
/// launch with a known version only records it; a changed version records
/// the new one and, when its switch is on, raises the short notice; the
/// available-update network check runs only when its switch is on.
({bool showUpdatedNotice, bool storeVersion, bool checkAvailable})
decideServerUpdateAlerts({
  required bool canManage,
  required String currentVersion,
  required String? lastSeenVersion,
  required bool informVersionUpdated,
  required bool informAvailableUpdate,
}) {
  const none = (
    showUpdatedNotice: false,
    storeVersion: false,
    checkAvailable: false,
  );
  if (!canManage || currentVersion.isBlank) return none;
  if (lastSeenVersion.isBlank) {
    return (
      showUpdatedNotice: false,
      storeVersion: true,
      checkAvailable: informAvailableUpdate,
    );
  }
  if (lastSeenVersion != currentVersion) {
    return (
      showUpdatedNotice: informVersionUpdated,
      storeVersion: true,
      checkAvailable: informAvailableUpdate,
    );
  }
  return (
    showUpdatedNotice: false,
    storeVersion: false,
    checkAvailable: informAvailableUpdate,
  );
}

/// True when [candidate] parses as a version newer than [current]. Anything
/// unparsable (or blank) means "no update", never a notice.
bool isNewerServerVersion(String current, String? candidate) {
  final tag = candidate?.trim();
  if (tag.isBlank) return false;
  String strip(String value) =>
      value.startsWith('v') ? value.substring(1) : value;
  try {
    return Version.parse(
      strip(tag!),
    ).compareTo(Version.parse(strip(current))).isGreaterThan(0);
  } catch (_) {
    return false;
  }
}
