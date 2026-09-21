import 'package:path/path.dart' as p;

const offlineAccountScopedKey = 'offline_catalog_account_scoped';
const offlineNonAccountScopedKey = 'offline_catalog_non_account_scoped';
const offlineNonAccountCatalogServerIdKey =
    'offline_non_account_catalog_server_id';
const offlineNonAccountLastServerIdKey = 'offline_non_account_last_server_id';
const offlineNonAccountLastServerAddressKey =
    'offline_non_account_last_server_address';

String nonAccountStoragePath(String offlineRoot) =>
    p.join(offlineRoot, 'non-account');

bool isNonAccountStoragePath(String storagePath) =>
    p.basename(storagePath) == 'non-account' &&
    p.basename(p.dirname(storagePath)) != 'accounts';

String accountStoragePath(String offlineRoot, String instanceId) {
  final match = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$',
  ).firstMatch(instanceId);
  if (match == null || match.end != instanceId.length) {
    throw ArgumentError.value(instanceId, 'instanceId');
  }
  return p.join(offlineRoot, 'accounts', instanceId);
}

String offlineControlRoot(String storagePath) {
  final parent = p.dirname(storagePath);
  if (isNonAccountStoragePath(storagePath)) return parent;
  if (p.basename(parent) != 'accounts') return storagePath;
  final root = p.dirname(parent);
  return p.normalize(accountStoragePath(root, p.basename(storagePath))) ==
          p.normalize(storagePath)
      ? root
      : storagePath;
}

bool isAccountStoragePath(String storagePath) =>
    !isNonAccountStoragePath(storagePath) &&
    offlineControlRoot(storagePath) != storagePath;
