import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../auth/data/auth_coordinator.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../auth/data/auth_state.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../settings/presentation/server/widget/credential_popup/login_credentials_popup.dart';
import '../domain/account_access.dart';
import 'account_notice.dart';
import 'account_permission.dart';
import 'account_providers.dart';
import 'account_repository.dart';
import 'graphql/__generated__/account.graphql.dart';
import 'graphql/__generated__/built_in_password.graphql.dart';

class AccountPasswordUnconfirmed implements Exception {
  const AccountPasswordUnconfirmed();
}

class AccountPasswordSignInRequired implements Exception {
  const AccountPasswordSignInRequired();
}

class AccountPasswordWhitespace implements Exception {
  const AccountPasswordWhitespace();
}

final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

class AccountActions {
  AccountActions(this.ref);
  final Ref ref;

  Future<void> refreshAccount() async {
    final current = ref
        .read(authCredentialsStoreProvider.notifier)
        .captureSession();
    final result = await ref
        .read(authCoordinatorProvider.notifier)
        .refreshUiAccessToken(
          gqlClient: ref.read(unauthenticatedGraphQlClientProvider),
          trigger: 'account-refresh',
        );
    if (!current()) throw StateError('Authentication session changed');
    if (result is RefreshTransientFailure) throw result.error;
    if (result is RefreshAuthFailure) {
      throw const AccountPasswordSignInRequired();
    }
    ref.invalidate(accountAccessProvider);
    await ref.read(accountAccessProvider.future);
  }

  Future<void> signOut() async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    await store.withIdentityChange(() async {
      await ref.read(accountNoticeProvider.notifier).set(null);
      await store.clearUiLoginTokens();
      await store.clearSimpleLoginCookie();
      await store.clearPassword();
      await store.clearBasicCredentials();
      ref.read(needsReauthProvider.notifier).set(false);
    }, expectedEpoch: store.serverEpoch);
  }

  Future<void> redeemCode({
    required String code,
    String? username,
    required String password,
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    final client = ref.read(unauthenticatedGraphQlClientProvider);
    final address = ref.read(currentServerAddressProvider);
    final coordinator = ref.read(authCoordinatorProvider.notifier);
    await store.withIdentityChange(() async {
      final epoch = store.serverEpoch;
      final repository = AccountRepository(client);
      final UiLoginTokens tokens;
      final String canonicalUsername;
      if (username != null) {
        final result = await repository.redeemRegistrationCode(
          Input$RedeemRegistrationCodeInput(
            code: code.trim(),
            username: username.trim(),
            password: password,
          ),
        );
        if (result == null) {
          throw StateError('Account registration returned no account');
        }
        tokens = UiLoginTokens(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        );
        canonicalUsername = result.user.username;
      } else {
        final result = await repository.redeemRecoveryCode(
          Input$RedeemRecoveryCodeInput(
            code: code.trim(),
            newPassword: password,
          ),
        );
        if (result == null) {
          throw StateError('Account recovery returned no account');
        }
        tokens = UiLoginTokens(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        );
        canonicalUsername = result.user.username;
      }
      await coordinator.adoptUiLoginTokens(
        gqlClient: client,
        tokens: tokens,
        forEpoch: epoch,
        address: address,
        username: canonicalUsername,
        password: password,
      );
      await store.clearSimpleLoginCookie();
      await store.clearBasicCredentials();
      ref.read(authUsernameProvider.notifier).update(canonicalUsername);
      ref.read(authTypeKeyProvider.notifier).update(AuthType.uiLogin);
    }, expectedEpoch: store.serverEpoch);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final store = ref.read(authCredentialsStoreProvider.notifier);
    final current = store.captureSession();
    final credentials = await ref.read(authCredentialsStoreProvider.future);
    final binding = credentials.accountBinding;
    if (!current() || binding?.userId == null) {
      throw StateError('This account cannot change its password here');
    }
    final builtIn = binding!.userId == 1;
    if (builtIn && (newPassword.isEmpty || newPassword.trim() != newPassword)) {
      throw const AccountPasswordWhitespace();
    }
    final client = ref.read(unauthenticatedGraphQlClientProvider);
    final coordinator = ref.read(authCoordinatorProvider.notifier);
    final address = ref.read(currentServerAddressProvider);
    if (!builtIn) {
      final refresh = await coordinator.refreshUiAccessTokenIfDue(
        gqlClient: client,
        trigger: 'account-check',
      );
      if (refresh is RefreshTransientFailure) throw refresh.error;
      if (refresh is RefreshAuthFailure || !current()) {
        throw const AccountPasswordSignInRequired();
      }
    }
    await store.withIdentityChange(() async {
      final epoch = store.serverEpoch;
      final accessToken = builtIn
          ? (await coordinator.verifyUiCredentials(
              gqlClient: client,
              username: binding.username,
              password: currentPassword,
            )).accessToken
          : store.uiLoginTokens()?.accessToken;
      if (accessToken == null) throw const AccountPasswordSignInRequired();
      final rotationClient = GraphQLClient(
        link: AuthLink(
          getToken: () => 'Bearer $accessToken',
        ).concat(client.link),
        cache: GraphQLCache(),
        queryRequestTimeout: client.queryManager.requestTimeout,
      );
      if (builtIn) {
        final user = await AccountRepository(rotationClient).current();
        if (user?.id != binding.userId) {
          throw StateError('Authentication account changed');
        }
        if (!AccountAccess(
          capability: AccountCapability.supported,
          user: user,
        ).allows(Enum$UserPermission.MANAGE_SETTINGS)) {
          throw const AccountPermissionDenied(
            Enum$UserPermission.MANAGE_SETTINGS,
          );
        }
      }
      if (builtIn &&
          await OfflineServerIdentityRepository(rotationClient).read() !=
              binding.catalogId) {
        throw StateError('Authentication server changed');
      }
      var confirmed = false;
      QueryResult<dynamic>? result;
      try {
        if (builtIn) {
          result = await rotationClient.mutate$SetBuiltInAccountPassword(
            Options$Mutation$SetBuiltInAccountPassword(
              fetchPolicy: FetchPolicy.noCache,
              variables: Variables$Mutation$SetBuiltInAccountPassword(
                input: Input$SetSettingsInput(
                  settings: Input$PartialSettingsTypeInput(
                    authPassword: newPassword,
                  ),
                ),
              ),
            ),
          );
        } else {
          result = await rotationClient.mutate$SetAccountPassword(
            Options$Mutation$SetAccountPassword(
              variables: Variables$Mutation$SetAccountPassword(
                input: Input$SetPasswordInput(
                  oldPassword: currentPassword,
                  newPassword: newPassword,
                ),
              ),
            ),
          );
        }
      } on Object {
        result = null;
      }
      final exception = result?.exception;
      if (exception != null &&
          exception.linkException == null &&
          exception.graphqlErrors.isNotEmpty) {
        throw exception;
      }
      confirmed =
          !builtIn &&
          result != null &&
          !result.hasException &&
          result.parsedData != null;
      try {
        UiLoginTokens? tokens;
        for (var attempt = 0; attempt < (builtIn ? 6 : 1); attempt++) {
          try {
            tokens = await coordinator.verifyUiCredentials(
              gqlClient: client,
              username: binding.username,
              password: newPassword,
            );
            break;
          } on OperationException catch (error) {
            if (!builtIn || attempt == 5 || error.linkException != null) {
              rethrow;
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
        await coordinator.adoptUiLoginTokens(
          gqlClient: client,
          tokens: tokens!,
          expectedBinding: binding,
          forEpoch: epoch,
          address: address,
          username: binding.username,
          password: newPassword,
        );
      } on Object {
        await ref
            .read(accountNoticeProvider.notifier)
            .set(
              confirmed
                  ? AccountNoticeKind.passwordSignInRequired
                  : AccountNoticeKind.passwordUnconfirmed,
            );
        await store.clearUiLoginTokens();
        await store.clearPassword();
        ref.read(needsReauthProvider.notifier).set(true);
        if (confirmed) throw const AccountPasswordSignInRequired();
        throw const AccountPasswordUnconfirmed();
      }
    }, expectedEpoch: store.serverEpoch);
  }
}
