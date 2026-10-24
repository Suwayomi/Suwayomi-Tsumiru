import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../../../account/data/account_permission.dart';
import '../graphql/__generated__/database.graphql.dart';

class DatabaseSettingsRepository {
  const DatabaseSettingsRepository(this.client, {required this.permissions});

  final GraphQLClient client;
  final AccountPermissionGuard permissions;

  Future<Fragment$DatabaseSettingsDto?> settings() async {
    try {
      return await client
          .query$DatabaseSettings(
            Options$Query$DatabaseSettings(fetchPolicy: FetchPolicy.noCache),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Query$PreviewDatabaseSettings$settings?> previewSettings() async {
    try {
      return await client
          .query$PreviewDatabaseSettings(
            Options$Query$PreviewDatabaseSettings(
              fetchPolicy: FetchPolicy.noCache,
            ),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Fragment$DatabaseSettingsDto?> write(
    Input$PartialSettingsTypeInput patch,
  ) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$SetDatabaseSettings(
          Options$Mutation$SetDatabaseSettings(
            variables: Variables$Mutation$SetDatabaseSettings(settings: patch),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );
}

final databaseSettingsRepositoryProvider = Provider<DatabaseSettingsRepository>(
  (ref) => DatabaseSettingsRepository(
    ref.watch(graphQlClientProvider),
    permissions: ref.watch(accountPermissionGuardProvider),
  ),
);

final databaseSettingsProvider =
    FutureProvider.autoDispose<Fragment$DatabaseSettingsDto?>(
      (ref) => ref.watch(databaseSettingsRepositoryProvider).settings(),
    );

final previewDatabaseSettingsProvider =
    FutureProvider.autoDispose<Query$PreviewDatabaseSettings$settings?>(
      (ref) => ref.watch(databaseSettingsRepositoryProvider).previewSettings(),
    );
