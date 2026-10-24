import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/network/graphql_errors.dart';
import '../../offline/data/background/background_download_controller_shim.dart';
import '../../offline/data/offline_server_identity_repository.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../../settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';
import 'auth_credentials_store.dart';
import 'auth_state.dart';

class AuthRecoveryTarget extends Notifier<AuthType?> {
  @override
  AuthType? build() {
    ref.watch(currentServerAddressProvider);
    return null;
  }

  void set(AuthType? mode) => state = mode;
}

final authRecoveryTargetProvider =
    NotifierProvider<AuthRecoveryTarget, AuthType?>(AuthRecoveryTarget.new);

class AuthModeReconciler {
  AuthModeReconciler(this.ref);
  final Ref ref;
  String? _audience;
  bool _reading = false;

  Future<void> reconcile({bool authFailure = false}) async {
    if (_reading) return;
    final store = ref.read(authCredentialsStoreProvider.notifier);
    if (store.identityChanging) return;
    _reading = true;
    final current = store.captureSession();
    final address = ref.read(currentServerAddressProvider);
    final mode = ref.read(authTypeKeyProvider) ?? AuthType.none;
    try {
      final credentials = await ref.read(authCredentialsStoreProvider.future);
      final basic = await ref.read(credentialsProvider.future);
      if (!ref.mounted || !current()) return;
      final raw = ref.read(unauthenticatedGraphQlClientProvider);
      final headers = switch (mode) {
        AuthType.none => <String, String>{},
        AuthType.basic => {'Authorization': ?basic},
        AuthType.simpleLogin =>
          credentials.simpleLoginCookieHeader ?? <String, String>{},
        AuthType.uiLogin =>
          credentials.uiAuthorizationHeader ?? <String, String>{},
      };
      final client = GraphQLClient(
        cache: GraphQLCache(),
        queryRequestTimeout: raw.queryManager.requestTimeout,
        link: Link.function(
          (request, [forward]) => forward!(
            request.updateContextEntry<HttpLinkHeaders>(
              (entry) =>
                  HttpLinkHeaders(headers: {...?entry?.headers, ...headers}),
            ),
          ),
        ).concat(raw.link),
      );
      Query$ServerSignInStatus$settings? status;
      try {
        status = await client
            .query$ServerSignInStatus(
              Options$Query$ServerSignInStatus(
                fetchPolicy: FetchPolicy.noCache,
              ),
            )
            .getData((data) => data.settings);
      } catch (error) {
        final cause = error is OperationMessageException
            ? error.exception
            : error;
        authFailure =
            authFailure ||
            isAuthenticationRequired(cause) ||
            isBasicGatedNotFound(cause);
        status = await raw
            .query$ServerSignInStatus(
              Options$Query$ServerSignInStatus(
                fetchPolicy: FetchPolicy.noCache,
              ),
            )
            .getData((data) => data.settings);
      }
      if (!ref.mounted ||
          !current() ||
          address != ref.read(currentServerAddressProvider) ||
          status == null) {
        return;
      }
      final target = switch (status.authMode) {
        Enum$AuthMode.NONE => AuthType.none,
        Enum$AuthMode.BASIC_AUTH => AuthType.basic,
        Enum$AuthMode.SIMPLE_LOGIN => AuthType.simpleLogin,
        Enum$AuthMode.UI_LOGIN => AuthType.uiLogin,
        Enum$AuthMode.$unknown => null,
      };
      if (target == null) return;
      final audienceChanged =
          mode == AuthType.uiLogin &&
          target == AuthType.uiLogin &&
          _audience != null &&
          _audience != status.jwtAudience;
      _audience = status.jwtAudience;
      if (target == mode && !authFailure && !audienceChanged) return;
      if (target == AuthType.none) {
        await ref.read(backgroundDownloadControllerProvider).changeIdentity(
          () async {
            ref.read(authTypeKeyProvider.notifier).update(AuthType.none);
            await store.clearUiLoginTokens();
            await store.clearSimpleLoginCookie();
            await store.clearBasicCredentials();
            ref.read(authRecoveryTargetProvider.notifier).set(null);
            ref.read(needsReauthProvider.notifier).set(false);
          },
        );
      } else {
        if (audienceChanged) {
          await ref.read(backgroundDownloadControllerProvider).changeIdentity(
            () async {
              await store.clearUiLoginTokens();
              ref.read(authRecoveryTargetProvider.notifier).set(target);
              ref.read(needsReauthProvider.notifier).set(true);
            },
          );
        } else {
          ref.read(authRecoveryTargetProvider.notifier).set(target);
          ref.read(needsReauthProvider.notifier).set(true);
        }
      }
    } catch (_) {
      if (authFailure && ref.mounted && current()) {
        ref
            .read(authRecoveryTargetProvider.notifier)
            .set(ref.read(authRecoveryTargetProvider) ?? mode);
        ref.read(needsReauthProvider.notifier).set(true);
      }
    } finally {
      _reading = false;
    }
  }
}

final authModeReconcilerProvider = Provider<AuthModeReconciler>((ref) {
  ref.watch(currentServerAddressProvider);
  return AuthModeReconciler(ref);
});
