import 'package:graphql/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../global_providers/global_providers.dart';
import '../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../account/data/account_permission.dart';
import '../../../domain/settings/settings.dart';
import './graphql/__generated__/query.graphql.dart';

part 'browse_settings_repository.g.dart';

class BrowseSettingsRepository {
  const BrowseSettingsRepository(this.ferryClient, {required this.permissions});

  final AccountPermissionGuard permissions;

  final GraphQLClient ferryClient;

  Future<SettingsDto?> updateSourceInParallel(int maxSourcesInParallel) =>
      permissions.run(
        Enum$UserPermission.MANAGE_SETTINGS,
        () => ferryClient
            .mutate$UpdateSourceInParallel(
              Options$Mutation$UpdateSourceInParallel(
                variables: Variables$Mutation$UpdateSourceInParallel(
                  maxSourcesInParallel: maxSourcesInParallel,
                ),
              ),
            )
            .getData((data) => data.setSettings.settings),
      );

  Future<SettingsDto?> updateLocalSourcePath(String value) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => ferryClient
        .mutate$UpdateLocalSourcePath(
          Options$Mutation$UpdateLocalSourcePath(
            variables: Variables$Mutation$UpdateLocalSourcePath(
              localSourcePath: value,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );
}

@riverpod
BrowseSettingsRepository browseSettingsRepository(Ref ref) =>
    BrowseSettingsRepository(
      ref.watch(graphQlClientProvider),
      permissions: ref.watch(accountPermissionGuardProvider),
    );
