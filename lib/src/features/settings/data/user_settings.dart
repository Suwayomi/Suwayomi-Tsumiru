import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../account/data/account_permission.dart';
import '../../account/data/account_providers.dart';
import '../../account/data/account_repository.dart';
import '../../account/data/graphql/__generated__/account.graphql.dart';
import '../../account/domain/account_access.dart';
import '../controller/server_controller.dart';
import '../domain/settings/graphql/__generated__/fragment.graphql.dart';
import '../domain/settings/settings.dart';

final userSettingsProvider = FutureProvider<Fragment$AccountSettingsDto?>((
  ref,
) async {
  final accessFuture = ref.watch(accountAccessProvider.future);
  final repository = ref.watch(accountRepositoryProvider);
  final access = await accessFuture;
  if (access.capability == AccountCapability.unsupported) return null;
  if (access.capability != AccountCapability.supported) {
    throw StateError('Account settings unavailable');
  }
  final settings = await repository.settings();
  if (settings == null) throw StateError('Missing account settings');
  return settings;
});

SettingsDto mergeUserSettings(
  SettingsDto settings,
  Fragment$AccountSettingsDto user,
) => settings.copyWith(
  autoDownloadNewChapters: user.autoDownloadNewChapters,
  autoDownloadNewChaptersLimit: user.autoDownloadNewChaptersLimit,
  excludeEntryWithUnreadChapters: user.excludeEntryWithUnreadChapters,
  updateMangas: user.updateMangas,
  excludeCompleted: user.excludeCompleted,
  excludeNotStarted: user.excludeNotStarted,
  excludeUnreadChapters: user.excludeUnreadChapters,
  syncDataCategories: user.syncDataCategories,
  syncDataChapters: user.syncDataChapters,
  syncDataHistory: user.syncDataHistory,
  syncDataManga: user.syncDataManga,
  syncDataTracking: user.syncDataTracking,
  syncInterval: user.syncInterval,
  syncYomiApiKey: user.syncYomiApiKey,
  syncYomiEnabled: user.syncYomiEnabled,
  syncYomiHost: user.syncYomiHost,
);

final personalSettingsProvider = FutureProvider<SettingsDto?>((ref) async {
  final settingsFuture = ref.watch(settingsProvider.future);
  final userFuture = ref.watch(userSettingsProvider.future);
  final settings = await settingsFuture;
  final user = await userFuture;
  return settings == null || user == null
      ? settings
      : mergeUserSettings(settings, user);
});

class UserSettingsRouting {
  const UserSettingsRouting({
    required this.account,
    required this.access,
    required this.settings,
    required this.updated,
  });
  final AccountRepository account;
  final AccountAccess Function() access;
  final Future<SettingsDto?> Function() settings;
  final void Function() updated;

  Future<SettingsDto?> update(
    Input$PartialUserSettingsTypeInput patch,
    Future<SettingsDto?> Function() legacy,
  ) async {
    switch (access().capability) {
      case AccountCapability.unknown:
        throw StateError('Account settings unavailable');
      case AccountCapability.unsupported:
        return legacy();
      case AccountCapability.supported:
        final baseline = await settings();
        if (baseline == null) throw StateError('Settings unavailable');
        if (access().capability != AccountCapability.supported) {
          throw StateError('Account settings changed');
        }
        final result = await account.setSettings(
          Input$SetUserSettingsInput(userSettings: patch),
        );
        if (result == null) throw StateError('Missing account settings');
        updated();
        return mergeUserSettings(baseline, result);
    }
  }

  Future<SettingsDto?> global(Future<SettingsDto?> Function() action) async {
    if (!access().allows(Enum$UserPermission.MANAGE_SETTINGS)) {
      throw const AccountPermissionDenied(Enum$UserPermission.MANAGE_SETTINGS);
    }
    return action();
  }
}

final userSettingsRoutingProvider = Provider<UserSettingsRouting>((ref) {
  return UserSettingsRouting(
    account: ref.watch(accountRepositoryProvider),
    access: () => ref.read(settledAccountAccessProvider),
    settings: () => ref.read(settingsProvider.future),
    updated: () => ref.invalidate(userSettingsProvider),
  );
});
