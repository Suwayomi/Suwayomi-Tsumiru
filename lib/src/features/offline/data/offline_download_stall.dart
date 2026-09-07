import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import 'offline_download_providers.dart';
import 'offline_settings_providers.dart';

class OfflineDownloadsStalled extends Notifier<String?> {
  @override
  String? build() => ref
      .read(sharedPreferencesProvider)
      .getString(DBKeys.offlineDownloadsStalled.name);

  Future<void> set(String? reason) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final key = DBKeys.offlineDownloadsStalled.name;
    final saved = reason == null
        ? await prefs.remove(key)
        : await prefs.setString(key, reason);
    if (!saved) throw StateError('Could not persist download stall');
    if (ref.mounted) state = reason;
  }
}

final offlineDownloadsStalledProvider =
    NotifierProvider<OfflineDownloadsStalled, String?>(
      OfflineDownloadsStalled.new,
    );

class OfflineDownloadRestriction extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? reason) => state = reason;
}

final offlineDownloadRestrictionProvider =
    NotifierProvider<OfflineDownloadRestriction, String?>(
      OfflineDownloadRestriction.new,
    );

final effectiveDownloadStallProvider = Provider<String?>((ref) {
  if (ref.watch(offlineDownloadsPausedProvider) ?? false) return null;
  if (!(ref.watch(offlineHasPendingProvider).value ?? false)) return null;
  return ref.watch(offlineDownloadRestrictionProvider) ??
      ref.watch(offlineDownloadsStalledProvider);
});
