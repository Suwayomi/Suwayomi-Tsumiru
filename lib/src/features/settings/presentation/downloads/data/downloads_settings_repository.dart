import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../data/user_settings.dart';
import '../../../domain/settings/settings.dart';
import './graphql/__generated__/query.graphql.dart';

part 'downloads_settings_repository.g.dart';

class DownloadsSettingsRepository {
  const DownloadsSettingsRepository(this.ferryClient, {required this.routing});

  final UserSettingsRouting routing;

  final GraphQLClient ferryClient;

  Future<SettingsDto?> updateDownloadsLocation(String value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateDownloadsLocation(
          Options$Mutation$UpdateDownloadsLocation(
            variables: Variables$Mutation$UpdateDownloadsLocation(
              downloadsPath: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.global(legacy);
  }

  Future<SettingsDto?> updateDownloadAsCbz(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateDownloadAsCbz(
          Options$Mutation$UpdateDownloadAsCbz(
            variables: Variables$Mutation$UpdateDownloadAsCbz(
              downloadAsCbz: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.global(legacy);
  }

  Future<SettingsDto?> toggleAutoDownloadNewChapters(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$ToggleAutoDownloadNewChapters(
          Options$Mutation$ToggleAutoDownloadNewChapters(
            variables: Variables$Mutation$ToggleAutoDownloadNewChapters(
              autoDownloadNewChapters: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(autoDownloadNewChapters: value),
      legacy,
    );
  }

  Future<SettingsDto?> toggleExcludeEntryWithUnreadChapters(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$ToggleExcludeEntryWithUnreadChapters(
          Options$Mutation$ToggleExcludeEntryWithUnreadChapters(
            variables: Variables$Mutation$ToggleExcludeEntryWithUnreadChapters(
              excludeEntryWithUnreadChapters: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(excludeEntryWithUnreadChapters: value),
      legacy,
    );
  }

  Future<SettingsDto?> updateAutoDownloadNewChaptersLimit(int value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateAutoDownloadNewChaptersLimit(
          Options$Mutation$UpdateAutoDownloadNewChaptersLimit(
            variables: Variables$Mutation$UpdateAutoDownloadNewChaptersLimit(
              autoDownloadNewChaptersLimit: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(autoDownloadNewChaptersLimit: value),
      legacy,
    );
  }
}

@riverpod
DownloadsSettingsRepository downloadsSettingsRepository(Ref ref) =>
    DownloadsSettingsRepository(
      ref.watch(graphQlClientProvider),
      routing: ref.watch(userSettingsRoutingProvider),
    );
