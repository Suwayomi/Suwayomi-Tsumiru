import 'package:path/path.dart' as p;

String accountStoragePath(String offlineRoot, String instanceId) {
  final match = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$',
  ).firstMatch(instanceId);
  if (match == null || match.end != instanceId.length) {
    throw ArgumentError.value(instanceId, 'instanceId');
  }
  return p.join(offlineRoot, 'accounts', instanceId);
}
