import 'package:riverpod_annotation/riverpod_annotation.dart'
    show ProviderListenable;

import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../account/data/account_permission.dart';
import '../../account/data/account_providers.dart';
import '../../account/domain/account_access.dart';
import '../../auth/data/auth_credentials_store.dart';
import 'background/catchup_work_spec.dart';
import 'offline_runtime_storage.dart';

typedef DownloadPermissionRead = T Function<T>(ProviderListenable<T> provider);

bool downloadPermissionAllowed(DownloadPermissionRead read) {
  final access = read(settledAccountAccessProvider);
  if (!access.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS)) return false;
  return !downloadsPausedForPermission(read);
}

// A settled snapshot may be unknown mid-refresh; keep denial parking separate from fetched permission.
bool downloadsPausedForPermission(DownloadPermissionRead read) {
  final binding = read(authCredentialsStoreProvider).value?.accountBinding;
  return binding != null &&
      CatchupStateStore(
        read(sharedPreferencesProvider),
      ).downloadPermissionPaused(binding.catalogId);
}

/// Awaits the current refresh and judges its result directly, without rereading a potentially newer snapshot.
Future<bool> resolvedDownloadPermissionAllowed(
  DownloadPermissionRead read,
) async {
  final current = read(authCredentialsStoreProvider.notifier).captureSession();
  if (!current()) return false;
  final AccountAccess access;
  try {
    access = await read(accountAccessProvider.future);
  } on Object {
    return false;
  }
  if (!current() || access.capability == AccountCapability.unknown) {
    return false;
  }
  if (!access.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS)) return false;
  return !downloadsPausedForPermission(read);
}

Future<void> verifyDownloadPermission(DownloadPermissionRead read) async {
  final current = read(authCredentialsStoreProvider.notifier).captureSession();
  if (!current()) throw const AccountPermissionUnavailable();
  final AccountAccess access;
  try {
    access = await read(refreshAccountAccessProvider)();
  } on Object {
    throw const AccountPermissionUnavailable();
  }
  if (!current() || access.capability == AccountCapability.unknown) {
    throw const AccountPermissionUnavailable();
  }
  if (!access.allows(Enum$UserPermission.DOWNLOAD_CHAPTERS)) {
    throw const AccountPermissionDenied(Enum$UserPermission.DOWNLOAD_CHAPTERS);
  }
  // Use the fetched access above; another refresh can already make the settled snapshot unknown.
  if (downloadsPausedForPermission(read)) {
    throw const AccountPermissionUnavailable();
  }
}

Future<void> pauseDownloadsForPermission(DownloadPermissionRead read) async {
  final current = read(authCredentialsStoreProvider.notifier).captureSession();
  final binding = read(authCredentialsStoreProvider).value?.accountBinding;
  final runtime = read(offlineRuntimeStorageProvider);
  if (!current() || binding == null || runtime == null) return;
  await CatchupStateStore(
    read(sharedPreferencesProvider),
  ).recordDownloadPermission(
    binding.catalogId,
    allowed: false,
    expectedRevision: 0,
    isCurrent: current,
    baseDir: runtime.paths.baseDir,
  );
}
