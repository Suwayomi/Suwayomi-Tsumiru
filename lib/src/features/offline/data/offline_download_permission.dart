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

/// Whether a denial has parked downloads for this account's catalogue.
///
/// Separate from the permission check because a caller that has just refreshed
/// the account should judge permission on what it fetched, not on the settled
/// snapshot: that snapshot reads `unknown` while any refresh is in flight, and
/// under active downloads it refreshes constantly.
bool downloadsPausedForPermission(DownloadPermissionRead read) {
  final binding = read(authCredentialsStoreProvider).value?.accountBinding;
  return binding != null &&
      CatchupStateStore(
        read(sharedPreferencesProvider),
      ).downloadPermissionPaused(binding.catalogId);
}

/// Non-throwing sibling of [verifyDownloadPermission] for a launch-path caller
/// that needs a plain yes/no answer at several points in one pass. Waits for
/// any account-access refresh already in flight to settle and judges that
/// result directly, the same way [verifyDownloadPermission] does, instead of
/// re-reading the [settledAccountAccessProvider] snapshot: that snapshot can
/// still read `unknown` right after the wait, if another refresh (an active
/// download keeps one going almost constantly) started in the interim.
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
  // Only the parked-by-denial flag here. Re-reading the settled snapshot threw
  // away the access just fetched above and failed the save whenever another
  // refresh happened to be in flight.
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
