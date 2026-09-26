import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../offline/data/background/catchup_work_spec.dart';
import '../../offline/data/offline_runtime_storage.dart';
import '../../offline/data/server_reachability.dart';
import '../domain/account_access.dart';
import 'account_permission.dart';
import 'account_repository.dart';
import 'graphql/__generated__/account.graphql.dart';

final Provider<AccountRepository> accountRepositoryProvider =
    Provider<AccountRepository>((ref) {
      return AccountRepository(
        ref.watch(graphQlClientProvider),
        access: () {
          if (!ref.mounted) throw const AccountPermissionUnavailable();
          return ref.container.read(settledAccountAccessProvider);
        },
      );
    });

final accountAccessProvider = FutureProvider<AccountAccess>((ref) async {
  if (ref.watch(authTypeKeyProvider) != AuthType.uiLogin) {
    return AccountAccess(capability: AccountCapability.unsupported);
  }
  final repository = ref.watch(accountRepositoryProvider);
  final unreachable = ref.watch(serverUnreachableProvider);
  final credentials = await ref.watch(authCredentialsStoreProvider.future);
  if (unreachable || credentials.sessionChanging) {
    return AccountAccess(capability: AccountCapability.unknown);
  }
  final store = ref.read(authCredentialsStoreProvider.notifier);
  final current = store.captureSession();
  final epoch = store.sessionEpoch;
  bool valid() => ref.mounted && current();
  final binding = credentials.accountBinding;
  final permissionStore = binding == null
      ? null
      : CatchupStateStore(ref.read(sharedPreferencesProvider));
  await permissionStore?.reload();
  if (!valid()) throw StateError('Authentication session changed');
  final permissionRevision = binding == null
      ? 0
      : permissionStore!.downloadPermissionRevision(binding.catalogId);
  final capability = await repository.capability(stillWanted: valid);
  if (!valid()) throw StateError('Authentication session changed');
  if (capability == AccountCapability.unknown) {
    throw StateError('Could not verify account support');
  }
  if (capability != AccountCapability.supported) {
    return AccountAccess(capability: capability);
  }
  final user = await repository.current();
  if (!valid()) throw StateError('Authentication session changed');
  if (user == null || user.id <= 0 || user.username.isEmpty) {
    throw StateError('Could not verify the signed-in account');
  }
  if (binding?.userId != null) {
    if (binding!.userId != user.id) {
      throw StateError('The server returned a different account');
    }
    final preferences = ref.read(sharedPreferencesProvider);
    final saved = await store.commitForSession(epoch, () async {
      if (!valid()) throw StateError('Authentication session changed');
      final runtime = ref.read(offlineRuntimeStorageProvider);
      if (runtime != null) {
        await permissionStore!.recordDownloadPermission(
          binding.catalogId,
          allowed: AccountAccess(
            capability: capability,
            user: user,
          ).allows(Enum$UserPermission.DOWNLOAD_CHAPTERS),
          expectedRevision: permissionRevision,
          isCurrent: valid,
          baseDir: runtime.paths.baseDir,
        );
      }
      await preferences.setString(
        'account.current/${binding.catalogId}',
        jsonEncode({'catalogId': binding.catalogId, 'user': user.toJson()}),
      );
    });
    if (!saved || !valid()) throw StateError('Authentication session changed');
  }
  return AccountAccess(capability: AccountCapability.supported, user: user);
});

final settledAccountAccessProvider = Provider<AccountAccess>((ref) {
  ref.watch(authCredentialsStoreProvider);
  if (!ref.read(authCredentialsStoreProvider.notifier).sessionAdmitted) {
    return AccountAccess(capability: AccountCapability.unknown);
  }
  if (ref.watch(authTypeKeyProvider) != AuthType.uiLogin) {
    return AccountAccess(capability: AccountCapability.unsupported);
  }
  if (ref.read(authCredentialsStoreProvider.notifier).uiLoginTokens() == null ||
      ref.read(authCredentialsStoreProvider).value?.accountBinding == null) {
    return AccountAccess(capability: AccountCapability.unknown);
  }
  final credentials = ref.watch(authCredentialsStoreProvider).value;
  if (credentials?.sessionChanging == true) {
    return AccountAccess(capability: AccountCapability.unknown);
  }
  final binding = credentials!.accountBinding!;
  final key = '${binding.catalogId}/${binding.userId}';
  final cache = ref.read(_settledAccessCacheProvider);
  final access = ref.watch(accountAccessProvider);
  final fresh = access.hasError ? null : access.asData?.value;
  if (fresh != null && fresh.capability != AccountCapability.unknown) {
    cache.remember(key, fresh);
    return fresh;
  }
  // A re-check in flight, an unreachable server or a failed probe says nothing
  // new about the grants, so keep the last settled answer for this binding.
  // Dropping to unknown here made every reachability flip flash
  // permission-denied UI (the Downloads queue header jumped on a stalled
  // server). The server still enforces every permission.
  return cache.recall(key) ??
      AccountAccess(capability: AccountCapability.unknown);
});

class _SettledAccessCache {
  String? _key;
  AccountAccess? _access;

  void remember(String key, AccountAccess access) {
    _key = key;
    _access = access;
  }

  AccountAccess? recall(String key) => _key == key ? _access : null;
}

final _settledAccessCacheProvider = Provider<_SettledAccessCache>(
  (ref) => _SettledAccessCache(),
);

final currentAccountProvider = Provider<Fragment$AccountDto?>((ref) {
  if (ref.watch(authTypeKeyProvider) != AuthType.uiLogin) return null;
  final credentials = ref.watch(authCredentialsStoreProvider).value;
  if (credentials == null ||
      !ref.read(authCredentialsStoreProvider.notifier).sessionAdmitted) {
    return null;
  }
  final live = ref.watch(settledAccountAccessProvider).user;
  if (live != null) return live;
  final binding = credentials.accountBinding;
  if (binding?.userId == null) return null;
  final cached = ref
      .watch(sharedPreferencesProvider)
      .getString('account.current/${binding!.catalogId}');
  if (cached == null) return null;
  try {
    final data = jsonDecode(cached) as Map<String, dynamic>;
    if (data['catalogId'] != binding.catalogId) return null;
    final user = Fragment$AccountDto.fromJson(
      data['user'] as Map<String, dynamic>,
    );
    if (user.id != binding.userId || user.username.isEmpty) return null;
    return user;
  } on Object {
    return null;
  }
});

final refreshAccountAccessProvider = Provider<Future<AccountAccess> Function()>(
  (ref) {
    final current = watchAuthSession(ref);
    Completer<AccountAccess>? pending;
    ref.onDispose(() {
      if (pending?.isCompleted == false) {
        pending!.completeError(const AccountPermissionUnavailable());
      }
    });
    return () {
      if (!current()) return Future.error(const AccountPermissionUnavailable());
      if (pending != null) return pending!.future;
      final request = Completer<AccountAccess>();
      pending = request;
      ref.invalidate(accountAccessProvider);
      ref
          .read(accountAccessProvider.future)
          .then(
            (access) {
              if (request.isCompleted) return;
              if (!current()) {
                request.completeError(const AccountPermissionUnavailable());
              } else {
                request.complete(access);
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!request.isCompleted) request.completeError(error, stack);
            },
          );
      return request.future.whenComplete(() {
        if (identical(pending, request)) pending = null;
      });
    };
  },
);
