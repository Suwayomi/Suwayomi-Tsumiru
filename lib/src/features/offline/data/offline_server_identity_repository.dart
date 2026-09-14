// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../account/data/account_repository.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import 'background/catchup_work_spec.dart';
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

final verifiedServerInstanceIdProvider = FutureProvider<String>((ref) async {
  final preferences = ref.watch(sharedPreferencesProvider);
  final address = ref.watch(currentServerAddressProvider);
  final authType = ref.watch(authTypeKeyProvider);
  final repository = ref.watch(offlineServerIdentityRepositoryProvider);
  final credentials = await ref.watch(authCredentialsStoreProvider.future);
  final store = ref.read(authCredentialsStoreProvider.notifier);
  final sessionEpoch = store.sessionEpoch;
  final controls = CatchupStateStore(preferences);
  final identityEpoch = controls.identityEpoch;
  final current = store.captureSession();
  bool valid() =>
      ref.mounted &&
      current() &&
      !controls.identityChanging &&
      controls.identityEpoch == identityEpoch &&
      ref.read(currentServerAddressProvider) == address;
  if (!valid()) throw StateError('Authentication session changed');
  final binding = credentials.accountBinding;
  if (authType == AuthType.uiLogin && binding == null) {
    throw StateError('Account identity has not been verified');
  }
  try {
    if (authType == AuthType.uiLogin && binding!.userId != null) {
      final user = await AccountRepository(repository.client).current();
      if (!valid() || user?.id != binding.userId) {
        throw StateError('The server returned a different account');
      }
    }
    final id = await repository.resolve();
    if (!valid()) {
      throw StateError('Server identity changed during verification');
    }
    if (authType == AuthType.uiLogin && id != binding!.catalogId) {
      throw StateError('The server returned a different catalogue');
    }
    final committed = await store.commitForSession(sessionEpoch, () async {
      if (!valid()) {
        throw StateError('Server identity changed during verification');
      }
      await preferences.setString(DBKeys.offlineLastServerId.name, id);
      await preferences.setString(
        DBKeys.offlineLastServerAddress.name,
        address,
      );
      await controls.setIdentityAuthorized(true);
    });
    if (!committed) throw StateError('Authentication session changed');
    return id;
  } catch (_) {
    if (valid()) {
      await store.commitForSession(sessionEpoch, () async {
        if (valid()) await controls.setIdentityAuthorized(false);
      });
    }
    rethrow;
  }
});

@riverpod
Future<String> serverInstanceId(Ref ref) async {
  final preferences = ref.watch(sharedPreferencesProvider);
  final address = ref.watch(currentServerAddressProvider);
  final authType = ref.watch(authTypeKeyProvider);
  final verified = ref.watch(verifiedServerInstanceIdProvider);
  if (authType == AuthType.uiLogin) {
    final credentials = await ref.watch(authCredentialsStoreProvider.future);
    if (credentials.sessionChanging || credentials.accountBinding == null) {
      throw StateError('Account identity has not been verified');
    }
    return credentials.accountBinding!.catalogId;
  }
  if (!verified.isLoading && verified.asData != null) {
    return verified.requireValue;
  }
  final cachedId = preferences.getString(DBKeys.offlineLastServerId.name);
  final cachedAddress = preferences.getString(
    DBKeys.offlineLastServerAddress.name,
  );
  if (cachedId != null && cachedId.isNotEmpty && cachedAddress == address) {
    return cachedId;
  }
  return ref.watch(verifiedServerInstanceIdProvider.future);
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
