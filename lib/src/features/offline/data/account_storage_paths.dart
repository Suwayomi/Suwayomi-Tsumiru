import 'package:path/path.dart' as p;

const offlineAccountScopedKey = 'offline_catalog_account_scoped';

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
  if (p.basename(parent) != 'accounts') return storagePath;
  final root = p.dirname(parent);
  return p.normalize(accountStoragePath(root, p.basename(storagePath))) ==
          p.normalize(storagePath)
      ? root
      : storagePath;
}
