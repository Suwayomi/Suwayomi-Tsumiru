import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../data/user_settings.dart';
import './graphql/__generated__/query.graphql.dart';
import './syncyomi_settings_provider.dart';

part 'syncyomi_settings_repository.g.dart';

class SyncYomiSettingsRepository {
  const SyncYomiSettingsRepository(
    this.ferryClient, {
    required this.routing,
    required this.written,
  });

  final GraphQLClient ferryClient;
  final UserSettingsRouting routing;
  final void Function() written;

  Future<bool> updateEnabled(bool value) => _write(
    Input$PartialUserSettingsTypeInput(syncYomiEnabled: value),
    () => ferryClient
        .mutate$UpdateSyncYomiEnabled(
          Options$Mutation$UpdateSyncYomiEnabled(
            variables: Variables$Mutation$UpdateSyncYomiEnabled(
              syncYomiEnabled: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<bool> updateHost(String value) => _write(
    Input$PartialUserSettingsTypeInput(syncYomiHost: value.trim()),
    () => ferryClient
        .mutate$UpdateSyncYomiHost(
          Options$Mutation$UpdateSyncYomiHost(
            variables: Variables$Mutation$UpdateSyncYomiHost(
              syncYomiHost: value.trim(),
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<bool> updateApiKey(String value) => _write(
    Input$PartialUserSettingsTypeInput(syncYomiApiKey: value.trim()),
    () => ferryClient
        .mutate$UpdateSyncYomiApiKey(
          Options$Mutation$UpdateSyncYomiApiKey(
            variables: Variables$Mutation$UpdateSyncYomiApiKey(
              syncYomiApiKey: value.trim(),
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<bool> updateInterval(String value) => _write(
    Input$PartialUserSettingsTypeInput(syncInterval: value),
    () => ferryClient
        .mutate$UpdateSyncYomiInterval(
          Options$Mutation$UpdateSyncYomiInterval(
            variables: Variables$Mutation$UpdateSyncYomiInterval(
              syncInterval: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  Future<bool> updateSyncData({
    required bool manga,
    required bool chapters,
    required bool categories,
    required bool history,
    required bool tracking,
  }) => _write(
    Input$PartialUserSettingsTypeInput(
      syncDataManga: manga,
      syncDataChapters: chapters,
      syncDataCategories: categories,
      syncDataHistory: history,
      syncDataTracking: tracking,
    ),
    () => ferryClient
        .mutate$UpdateSyncYomiData(
          Options$Mutation$UpdateSyncYomiData(
            variables: Variables$Mutation$UpdateSyncYomiData(
              syncDataManga: manga,
              syncDataChapters: chapters,
              syncDataCategories: categories,
              syncDataHistory: history,
              syncDataTracking: tracking,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );

  /// A server old enough to need `setSettings` may not carry the shared fragment.
  Future<bool> _write(
    Input$PartialUserSettingsTypeInput patch,
    Future<void> Function() legacy,
  ) async {
    await routing.update(patch, () async {
      await legacy();
      return null;
    });
    written();
    return true;
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
      written: () => ref.invalidate(syncYomiSettingsProvider),
    );

@Riverpod(keepAlive: false)
Future<Query$LastSyncStatus$lastSyncStatus?> lastSyncStatus(Ref ref) =>
    ref.watch(syncyomiSettingsRepositoryProvider).lastSyncStatus();
