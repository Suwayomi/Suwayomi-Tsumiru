import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../../../account/data/account_permission.dart';
import '../graphql/__generated__/misc_logs.graphql.dart';

class MiscLogsRepository {
  const MiscLogsRepository(this.client, {required this.permissions});

  final GraphQLClient client;
  final AccountPermissionGuard permissions;

  Future<Fragment$MiscLogsSettingsDto?> settings() async {
    try {
      return await client
          .query$MiscLogsSettings(
            Options$Query$MiscLogsSettings(fetchPolicy: FetchPolicy.noCache),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Fragment$MiscLogsSettingsDto?> write(
    Input$PartialSettingsTypeInput patch,
  ) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$SetMiscLogsSettings(
          Options$Mutation$SetMiscLogsSettings(
            variables: Variables$Mutation$SetMiscLogsSettings(
              settings: patch,
            ),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );
}

final miscLogsRepositoryProvider = Provider<MiscLogsRepository>(
  (ref) => MiscLogsRepository(
    ref.watch(graphQlClientProvider),
    permissions: ref.watch(accountPermissionGuardProvider),
  ),
);

final miscLogsSettingsProvider =
    FutureProvider.autoDispose<Fragment$MiscLogsSettingsDto?>(
      (ref) => ref.watch(miscLogsRepositoryProvider).settings(),
    );
