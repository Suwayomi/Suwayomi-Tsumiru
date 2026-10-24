import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../../utils/misc/graphql_undefined_field.dart';
import '../../../../../../account/data/account_permission.dart';
import '../graphql/__generated__/sign_in.graphql.dart';

class SignInSettingsRepository {
  const SignInSettingsRepository(this.client, {required this.permissions});

  final GraphQLClient client;
  final AccountPermissionGuard permissions;

  Future<Fragment$SignInSettingsDto?> settings() async {
    try {
      return await client
          .query$SignInSettings(
            Options$Query$SignInSettings(fetchPolicy: FetchPolicy.noCache),
          )
          .getData((data) => data.settings);
    } on OperationMessageException catch (error) {
      if (onlyUndefinedFieldErrors(error, type: 'SettingsType')) return null;
      rethrow;
    }
  }

  Future<Fragment$SignInSettingsDto?> write(
    Input$PartialSettingsTypeInput patch,
  ) => permissions.run(
    Enum$UserPermission.MANAGE_SETTINGS,
    () => client
        .mutate$SetSignInSettings(
          Options$Mutation$SetSignInSettings(
            variables: Variables$Mutation$SetSignInSettings(settings: patch),
          ),
        )
        .getData((data) => data.setSettings.settings),
  );
}

final signInSettingsRepositoryProvider = Provider<SignInSettingsRepository>(
  (ref) => SignInSettingsRepository(
    ref.watch(graphQlClientProvider),
    permissions: ref.watch(accountPermissionGuardProvider),
  ),
);

final signInSettingsProvider =
    FutureProvider.autoDispose<Fragment$SignInSettingsDto?>(
      (ref) => ref.watch(signInSettingsRepositoryProvider).settings(),
    );
