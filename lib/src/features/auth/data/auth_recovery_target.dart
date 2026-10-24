import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../account/data/account_providers.dart';
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
  bool _reading = false;

  Future<void> reconcile({bool authFailure = false}) async {
    if (!authFailure ||
        _reading ||
        ref.read(authRecoveryTargetProvider) != null) {
      return;
    }
    final store = ref.read(authCredentialsStoreProvider.notifier);
    if (store.identityChanging) return;
    _reading = true;
    final current = store.captureSession();
    final mode = ref.read(authTypeKeyProvider) ?? AuthType.none;
    var target = ref.read(authRecoveryTargetProvider) ?? mode;
    try {
      final access = ref.read(settledAccountAccessProvider);
      if (access.user != null &&
          access.allows(Enum$UserPermission.MANAGE_SETTINGS)) {
        final credentials = await ref.read(authCredentialsStoreProvider.future);
        final basic = await ref.read(credentialsProvider.future);
        if (!ref.mounted || !current()) return;
        final headers = switch (mode) {
          AuthType.none => <String, String>{},
          AuthType.basic => {'Authorization': ?basic},
          AuthType.simpleLogin =>
            credentials.simpleLoginCookieHeader ?? <String, String>{},
          AuthType.uiLogin =>
            credentials.uiAuthorizationHeader ?? <String, String>{},
        };
        final raw = ref.read(unauthenticatedGraphQlClientProvider);
        final client = GraphQLClient(
          link: Link.function(
            (request, [forward]) => forward!(
              request.updateContextEntry<HttpLinkHeaders>(
                (entry) =>
                    HttpLinkHeaders(headers: {...?entry?.headers, ...headers}),
              ),
            ),
          ).concat(raw.link),
          cache: GraphQLCache(),
          queryRequestTimeout: raw.queryManager.requestTimeout,
        );
        final status = await client
            .query$ServerSignInStatus(
              Options$Query$ServerSignInStatus(
                fetchPolicy: FetchPolicy.noCache,
              ),
            )
            .getData((data) => data.settings);
        if (status != null) {
          target = switch (status.authMode) {
            Enum$AuthMode.NONE => AuthType.none,
            Enum$AuthMode.BASIC_AUTH => AuthType.basic,
            Enum$AuthMode.SIMPLE_LOGIN => AuthType.simpleLogin,
            Enum$AuthMode.UI_LOGIN => AuthType.uiLogin,
            Enum$AuthMode.$unknown => target,
          };
        }
      }
    } catch (_) {
      // Protected settings may be unreadable after an external mode change.
    } finally {
      _reading = false;
      if (ref.mounted && current()) {
        ref
            .read(authRecoveryTargetProvider.notifier)
            .set(ref.read(authRecoveryTargetProvider) ?? target);
        ref.read(needsReauthProvider.notifier).set(true);
      }
    }
  }
}

final authModeReconcilerProvider = Provider<AuthModeReconciler>((ref) {
  ref.watch(currentServerAddressProvider);
  return AuthModeReconciler(ref);
});
