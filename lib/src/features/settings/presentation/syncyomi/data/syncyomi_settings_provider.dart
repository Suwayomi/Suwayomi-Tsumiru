import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../account/data/graphql/__generated__/account.graphql.dart';
import '../../../../account/domain/account_access.dart';
import '../../../data/user_settings.dart';
import '../../../domain/settings/graphql/__generated__/fragment.graphql.dart';
import './graphql/__generated__/query.graphql.dart';

class SyncYomiSettings {
  const SyncYomiSettings({
    required this.enabled,
    required this.host,
    required this.apiKey,
    required this.interval,
    required this.dataManga,
    required this.dataChapters,
    required this.dataCategories,
    required this.dataHistory,
    required this.dataTracking,
  });

  factory SyncYomiSettings.fromUser(Fragment$AccountSettingsDto user) =>
      SyncYomiSettings(
        enabled: user.syncYomiEnabled,
        host: user.syncYomiHost,
        apiKey: user.syncYomiApiKey,
        interval: user.syncInterval,
        dataManga: user.syncDataManga,
        dataChapters: user.syncDataChapters,
        dataCategories: user.syncDataCategories,
        dataHistory: user.syncDataHistory,
        dataTracking: user.syncDataTracking,
      );

  factory SyncYomiSettings.fromLegacy(Fragment$SyncYomiSettingsDto settings) =>
      SyncYomiSettings(
        enabled: settings.syncYomiEnabled,
        host: settings.syncYomiHost,
        apiKey: settings.syncYomiApiKey,
        interval: settings.syncInterval,
        dataManga: settings.syncDataManga,
        dataChapters: settings.syncDataChapters,
        dataCategories: settings.syncDataCategories,
        dataHistory: settings.syncDataHistory,
        dataTracking: settings.syncDataTracking,
      );

  final bool enabled;
  final String host;
  final String apiKey;
  final String interval;
  final bool dataManga;
  final bool dataChapters;
  final bool dataCategories;
  final bool dataHistory;
  final bool dataTracking;
}

/// Null means the server has no SyncYomi settings at all.
final syncYomiSettingsProvider = FutureProvider<SyncYomiSettings?>((ref) async {
  // Only the capability picks the source. Watching the whole access re-ran
  // the legacy query on every account re-check, even when nothing changed.
  switch (ref.watch(
    settledAccountAccessProvider.select((access) => access.capability),
  )) {
    case AccountCapability.supported:
      final user = await ref.watch(userSettingsProvider.future);
      return user == null ? null : SyncYomiSettings.fromUser(user);
    case AccountCapability.unsupported:
      return _legacySettings(ref);
    case AccountCapability.unknown:
      throw StateError('Account settings unavailable');
  }
});

Future<SyncYomiSettings?> _legacySettings(Ref ref) async {
  final result = await ref
      .watch(graphQlClientProvider)
      .query$SyncYomiLegacySettings(Options$Query$SyncYomiLegacySettings());
  final exception = result.exception;
  if (exception != null) {
    final errors = exception.graphqlErrors;
    if (errors.isNotEmpty &&
        errors.every((e) => isUndefinedFieldError(e, type: 'SettingsType'))) {
      return null;
    }
    throw OperationMessageException(exception);
  }
  final settings = result.parsedData?.settings;
  return settings == null ? null : SyncYomiSettings.fromLegacy(settings);
}
