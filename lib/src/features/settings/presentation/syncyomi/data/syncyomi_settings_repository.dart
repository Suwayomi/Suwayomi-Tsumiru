import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../data/user_settings.dart';
import '../../../domain/settings/settings.dart';
import './graphql/__generated__/query.graphql.dart';

part 'syncyomi_settings_repository.g.dart';

class SyncYomiSettingsRepository {
  const SyncYomiSettingsRepository(this.ferryClient, {required this.routing});

  final UserSettingsRouting routing;

  final GraphQLClient ferryClient;

  Future<SettingsDto?> updateEnabled(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateSyncYomiEnabled(
          Options$Mutation$UpdateSyncYomiEnabled(
            variables: Variables$Mutation$UpdateSyncYomiEnabled(
              syncYomiEnabled: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(syncYomiEnabled: value),
      legacy,
    );
  }

  Future<SettingsDto?> updateHost(String value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateSyncYomiHost(
          Options$Mutation$UpdateSyncYomiHost(
            variables: Variables$Mutation$UpdateSyncYomiHost(
              syncYomiHost: value.trim(),
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(syncYomiHost: value.trim()),
      legacy,
    );
  }

  Future<SettingsDto?> updateApiKey(String value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateSyncYomiApiKey(
          Options$Mutation$UpdateSyncYomiApiKey(
            variables: Variables$Mutation$UpdateSyncYomiApiKey(
              syncYomiApiKey: value.trim(),
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(syncYomiApiKey: value.trim()),
      legacy,
    );
  }

  Future<SettingsDto?> updateInterval(String value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateSyncYomiInterval(
          Options$Mutation$UpdateSyncYomiInterval(
            variables: Variables$Mutation$UpdateSyncYomiInterval(
              syncInterval: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(syncInterval: value),
      legacy,
    );
  }

  Future<Enum$StartSyncResult> startSync() async {
    final result = await ferryClient
        .mutate$StartSync(Options$Mutation$StartSync())
        .getData((data) => data.startSync.result);
    if (result == null) throw StateError('Sync returned no result');
    return result;
  }

  Future<Query$LastSyncStatus$lastSyncStatus?> lastSyncStatus() => ferryClient
      .query$LastSyncStatus(Options$Query$LastSyncStatus())
      .getData((data) => data.lastSyncStatus);
}

@riverpod
SyncYomiSettingsRepository syncyomiSettingsRepository(Ref ref) =>
    SyncYomiSettingsRepository(
      ref.watch(graphQlClientProvider),
      routing: ref.watch(userSettingsRoutingProvider),
    );

@Riverpod(keepAlive: false)
Future<Query$LastSyncStatus$lastSyncStatus?> lastSyncStatus(Ref ref) =>
    ref.watch(syncyomiSettingsRepositoryProvider).lastSyncStatus();
