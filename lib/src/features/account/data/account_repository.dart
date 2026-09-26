import 'package:graphql/client.dart';

import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/crash/diagnostics.dart';
import '../../../utils/crash/redact_tokens.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../domain/account_access.dart';
import 'account_permission.dart';
import 'graphql/__generated__/account.graphql.dart';

class AccountRepository {
  const AccountRepository(this.client, {this.access});

  final AccountAccess Function()? access;

  Future<T> _admin<T>(Future<T> Function() action) async {
    final current = access?.call();
    if (current?.canManageUsers != true) {
      throw const AccountPermissionDenied(Enum$UserPermission.MANAGE_USERS);
    }
    return AccountPermissionGuard(
      () => access!(),
    ).run(Enum$UserPermission.MANAGE_USERS, action);
  }

  final GraphQLClient client;

  /// [stillWanted] tells whether the caller still uses the answer. An endpoint
  /// switch replaces the GraphQL client and rebuilds the provider asking, and
  /// the superseded build's query dies with the old client ("Cannot use the
  /// Ref of graphQlClientProvider after it has been disposed"). That answer is
  /// thrown away, so it isn't logged as a failed check.
  Future<AccountCapability> capability({bool Function()? stillWanted}) async {
    final result = await client.query$AccountCapability();
    final capability = classifyAccountResponse(result);
    if (capability == AccountCapability.unknown &&
        (stillWanted?.call() ?? true)) {
      // accountAccessProvider turns `unknown` into "Could not verify account
      // support", which fails the library's default category and category
      // lists; the response that caused it was dropped.
      recordDiagnostic(
        redactTokens(
          '[${DateTime.now().toIso8601String()}] account-capability: unknown '
          '${describeAccountResponse(result)}\n',
        ),
      );
    }
    return capability;
  }

  Future<Fragment$AccountDto?> current() =>
      client.query$CurrentAccount().getData((data) => data.user);

  Future<Query$Accounts$users?> users({
    required int first,
    int? after,
    String? search,
  }) => _admin(
    () => client
        .query$Accounts(
          Options$Query$Accounts(
            fetchPolicy: FetchPolicy.networkOnly,
            variables: Variables$Query$Accounts(
              first: first,
              after: after,
              filter: search == null || search.trim().isEmpty
                  ? null
                  : Input$UserFilterInput(
                      username: Input$StringFilterInput(
                        includesInsensitive: search.trim(),
                      ),
                    ),
            ),
          ),
        )
        .getData((data) => data.users),
  );

  Future<List<Fragment$AccountCodeDto>?> codes({int? forUserId}) => _admin(
    () => client
        .query$AccountCodes(
          Options$Query$AccountCodes(
            fetchPolicy: FetchPolicy.networkOnly,
            variables: Variables$Query$AccountCodes(forUserId: forUserId),
          ),
        )
        .getData((data) => data.userCodes),
  );

  Future<Fragment$AccountSettingsDto?> settings() =>
      client.query$AccountSettings().getData((data) => data.userSettings);

  Future<void> register(Input$RegisterInput input) => _admin(
    () => client
        .mutate$RegisterAccount(
          Options$Mutation$RegisterAccount(
            fetchPolicy: FetchPolicy.noCache,
            variables: Variables$Mutation$RegisterAccount(input: input),
          ),
        )
        .getData((data) {}),
  );

  Future<Mutation$CreateRegistrationCode$createRegistrationCode?>
  createRegistrationCode(Input$CreateRegistrationCodeInput input) => _admin(
    () => client
        .mutate$CreateRegistrationCode(
          Options$Mutation$CreateRegistrationCode(
            fetchPolicy: FetchPolicy.noCache,
            variables: Variables$Mutation$CreateRegistrationCode(input: input),
          ),
        )
        .getData((data) => data.createRegistrationCode),
  );

  Future<Mutation$RedeemRegistrationCode$redeemRegistrationCode?>
  redeemRegistrationCode(Input$RedeemRegistrationCodeInput input) => client
      .mutate$RedeemRegistrationCode(
        Options$Mutation$RedeemRegistrationCode(
          variables: Variables$Mutation$RedeemRegistrationCode(input: input),
        ),
      )
      .getData((data) => data.redeemRegistrationCode);

  Future<Mutation$CreateRecoveryCode$createRecoveryCode?> createRecoveryCode(
    Input$CreateRecoveryCodeInput input,
  ) => _admin(() {
    if (input.userId == 1) {
      throw const AccountPermissionDenied(Enum$UserPermission.MANAGE_USERS);
    }
    return client
        .mutate$CreateRecoveryCode(
          Options$Mutation$CreateRecoveryCode(
            fetchPolicy: FetchPolicy.noCache,
            variables: Variables$Mutation$CreateRecoveryCode(input: input),
          ),
        )
        .getData((data) => data.createRecoveryCode);
  });

  Future<Mutation$RedeemRecoveryCode$redeemRecoveryCode?> redeemRecoveryCode(
    Input$RedeemRecoveryCodeInput input,
  ) => client
      .mutate$RedeemRecoveryCode(
        Options$Mutation$RedeemRecoveryCode(
          variables: Variables$Mutation$RedeemRecoveryCode(input: input),
        ),
      )
      .getData((data) => data.redeemRecoveryCode);

  Future<void> revokeCode(Input$RevokeUserCodeInput input) => _admin(
    () => client
        .mutate$RevokeAccountCode(
          Options$Mutation$RevokeAccountCode(
            variables: Variables$Mutation$RevokeAccountCode(input: input),
          ),
        )
        .getData((data) {}),
  );

  Future<Fragment$AccountDto?> updateAccount(Input$UpdateUserInput input) =>
      _admin(() {
        if (input.userId == 1 ||
            (input.role != null && access?.call().canEditRoles != true)) {
          throw const AccountPermissionDenied(Enum$UserPermission.MANAGE_USERS);
        }
        return client
            .mutate$UpdateAccount(
              Options$Mutation$UpdateAccount(
                variables: Variables$Mutation$UpdateAccount(input: input),
              ),
            )
            .getData((data) => data.updateUser.user);
      });

  Future<void> setPassword(Input$SetPasswordInput input) => client
      .mutate$SetAccountPassword(
        Options$Mutation$SetAccountPassword(
          variables: Variables$Mutation$SetAccountPassword(input: input),
        ),
      )
      .getData((data) {});

  Future<Fragment$AccountSettingsDto?> setSettings(
    Input$SetUserSettingsInput input,
  ) => client
      .mutate$SetAccountSettings(
        Options$Mutation$SetAccountSettings(
          variables: Variables$Mutation$SetAccountSettings(input: input),
        ),
      )
      .getData((data) => data.setUserSettings.userSettings);

  Future<Fragment$AccountSettingsDto?> resetSettings(
    Input$ResetUserSettingsInput input,
  ) => client
      .mutate$ResetAccountSettings(
        Options$Mutation$ResetAccountSettings(
          variables: Variables$Mutation$ResetAccountSettings(input: input),
        ),
      )
      .getData((data) => data.resetUserSettings.userSettings);
}
