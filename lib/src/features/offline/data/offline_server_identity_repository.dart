// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'graphql/__generated__/server_identity.graphql.dart';
import 'offline_server_identity.dart';

part 'offline_server_identity_repository.g.dart';

class OfflineServerIdentityRepository {
  const OfflineServerIdentityRepository(this.client);

  final GraphQLClient client;

  Future<String?> read() => client
      .query$OfflineServerIdentity(
        Options$Query$OfflineServerIdentity(
          variables: Variables$Query$OfflineServerIdentity(
            key: kTsumiruServerIdMetaKey,
          ),
        ),
      )
      .getData((data) => data.metas.nodes.firstOrNull?.value);

  Future<void> write(String value) => client
      .mutate$SetOfflineServerIdentity(
        Options$Mutation$SetOfflineServerIdentity(
          variables: Variables$Mutation$SetOfflineServerIdentity(
            key: kTsumiruServerIdMetaKey,
            value: value,
          ),
        ),
      )
      .getData((data) => data.setGlobalMeta?.meta.value);

  Future<String> resolve() => resolveServerInstanceId(
        read: read,
        write: write,
        create: createServerInstanceId,
      );
}

Future<String> resolveServerInstanceId({
  required Future<String?> Function() read,
  required Future<void> Function(String value) write,
  required String Function() create,
}) async {
  final existing = await read();
  if (existing != null && existing.isNotEmpty) return existing;
  await write(create());
  final stored = await read();
  if (stored == null || stored.isEmpty) {
    throw StateError('Server identity was not persisted');
  }
  return stored;
}

@riverpod
OfflineServerIdentityRepository offlineServerIdentityRepository(Ref ref) =>
    OfflineServerIdentityRepository(ref.watch(graphQlClientProvider));

@riverpod
String currentServerAddress(Ref ref) => serverAddress(
      baseUrl: ref.watch(serverUrlProvider),
      port: ref.watch(serverPortProvider),
      addPort: ref.watch(serverPortToggleProvider).ifNull(),
    );

@riverpod
Future<String> serverInstanceId(Ref ref) async {
  final preferences = ref.watch(sharedPreferencesProvider);
  final address = ref.watch(currentServerAddressProvider);
  final cachedId = preferences.getString(DBKeys.offlineLastServerId.name);
  final cachedAddress =
      preferences.getString(DBKeys.offlineLastServerAddress.name);

  // Offline-first: if we already know this address's id, return it immediately
  // (no network wait, so the offline library opens instantly) and verify against
  // the server in the background — a genuine switch is still caught a moment
  // later, without blocking offline reads on a live round-trip.
  if (cachedId != null && cachedId.isNotEmpty && cachedAddress == address) {
    unawaited(_verifyServerInstanceId(ref, preferences, address, cachedId));
    return cachedId;
  }

  // First time on this address: resolve online and cache it.
  return _resolveAndCacheServerInstanceId(ref, preferences, address);
}

Future<void> _verifyServerInstanceId(
  Ref ref,
  SharedPreferences preferences,
  String address,
  String cachedId,
) async {
  try {
    final live =
        await ref.read(offlineServerIdentityRepositoryProvider).resolve();
    if (live == cachedId) return;
    // The address now points at a different server — record its id and
    // re-evaluate so the mismatch guard/banner picks up the switch.
    await preferences.setString(DBKeys.offlineLastServerId.name, live);
    await preferences.setString(DBKeys.offlineLastServerAddress.name, address);
    ref.invalidateSelf();
  } catch (_) {
    // Unreachable / server error → keep trusting the cached id (a token lapse
    // or a 500 on the same address is not evidence of a server switch).
  }
}

Future<String> _resolveAndCacheServerInstanceId(
  Ref ref,
  SharedPreferences preferences,
  String address,
) async {
  try {
    final id =
        await ref.read(offlineServerIdentityRepositoryProvider).resolve();
    await preferences.setString(DBKeys.offlineLastServerId.name, id);
    await preferences.setString(DBKeys.offlineLastServerAddress.name, address);
    return id;
  } catch (error) {
    final cachedAddress =
        preferences.getString(DBKeys.offlineLastServerAddress.name);
    final cachedId = preferences.getString(DBKeys.offlineLastServerId.name);
    final fallback = cachedServerIdForFailure(
      error: error,
      currentAddress: address,
      cachedAddress: cachedAddress,
      cachedId: cachedId,
    );
    if (fallback != null) return fallback;
    rethrow;
  }
}

String? cachedServerIdForFailure({
  required Object error,
  required String currentAddress,
  required String? cachedAddress,
  required String? cachedId,
}) {
  final cause = error is OperationMessageException ? error.exception : error;
  if (!isConnectionError(cause) ||
      cachedAddress != currentAddress ||
      cachedId == null ||
      cachedId.isEmpty) {
    return null;
  }
  return cachedId;
}
