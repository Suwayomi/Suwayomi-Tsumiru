import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../data/user_settings.dart';
import '../../../domain/settings/settings.dart';
import './graphql/__generated__/query.graphql.dart';

part 'library_settings_repository.g.dart';

class LibrarySettingsRepository {
  const LibrarySettingsRepository(this.ferryClient, {required this.routing});

  final UserSettingsRouting routing;

  final GraphQLClient ferryClient;

  Future<SettingsDto?> updateGlobalUpdateInterval(double value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateGlobalUpdateInterval(
          Options$Mutation$UpdateGlobalUpdateInterval(
            variables: Variables$Mutation$UpdateGlobalUpdateInterval(
              globalUpdateInterval: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.global(legacy);
  }

  Future<SettingsDto?> updateMangaMetaData(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$UpdateMangaMetaData(
          Options$Mutation$UpdateMangaMetaData(
            variables: Variables$Mutation$UpdateMangaMetaData(
              updateMangas: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(updateMangas: value),
      legacy,
    );
  }

  Future<SettingsDto?> toggleExcludeCompleted(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$ToggleExcludeCompleted(
          Options$Mutation$ToggleExcludeCompleted(
            variables: Variables$Mutation$ToggleExcludeCompleted(
              excludeCompleted: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(excludeCompleted: value),
      legacy,
    );
  }

  Future<SettingsDto?> toggleExcludeNotStarted(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$ToggleExcludeNotStarted(
          Options$Mutation$ToggleExcludeNotStarted(
            variables: Variables$Mutation$ToggleExcludeNotStarted(
              excludeNotStarted: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(excludeNotStarted: value),
      legacy,
    );
  }

  Future<SettingsDto?> toggleExcludeUnreadChapters(bool value) {
    Future<SettingsDto?> legacy() => ferryClient
        .mutate$ToggleExcludeUnreadChapters(
          Options$Mutation$ToggleExcludeUnreadChapters(
            variables: Variables$Mutation$ToggleExcludeUnreadChapters(
              excludeUnreadChapters: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings);
    return routing.update(
      Input$PartialUserSettingsTypeInput(excludeUnreadChapters: value),
      legacy,
    );
  }
}

@riverpod
LibrarySettingsRepository librarySettingsRepository(Ref ref) =>
    LibrarySettingsRepository(
      ref.watch(graphQlClientProvider),
      routing: ref.watch(userSettingsRoutingProvider),
    );
