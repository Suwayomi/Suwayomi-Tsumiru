import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../account/data/account_providers.dart';
import '../../../../account/domain/account_access.dart';
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

  Future<bool?> legacyAutoDownloadIgnoreReUploads() => ferryClient
      .query$AutoDownloadIgnoreReUploadsLegacy(
        Options$Query$AutoDownloadIgnoreReUploadsLegacy(
          fetchPolicy: FetchPolicy.noCache,
        ),
      )
      .getData((data) => data.settings.autoDownloadIgnoreReUploads);

  Future<SettingsDto?> toggleAutoDownloadIgnoreReUploads(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$ToggleAutoDownloadIgnoreReUploads(
          Options$Mutation$ToggleAutoDownloadIgnoreReUploads(
            variables: Variables$Mutation$ToggleAutoDownloadIgnoreReUploads(
              autoDownloadIgnoreReUploads: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(autoDownloadIgnoreReUploads: value),
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

final autoDownloadIgnoreReUploadsProvider = FutureProvider.autoDispose<bool?>((
  ref,
) async {
  switch (ref.watch(settledAccountAccessProvider).capability) {
    case AccountCapability.supported:
      return (await ref.watch(
        userSettingsProvider.future,
      ))?.autoDownloadIgnoreReUploads;
    case AccountCapability.unsupported:
      try {
        return await ref
            .watch(downloadsSettingsRepositoryProvider)
            .legacyAutoDownloadIgnoreReUploads();
      } on OperationMessageException catch (error) {
        if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) {
          return null;
        }
        rethrow;
      }
    case AccountCapability.unknown:
      return null;
  }
});
