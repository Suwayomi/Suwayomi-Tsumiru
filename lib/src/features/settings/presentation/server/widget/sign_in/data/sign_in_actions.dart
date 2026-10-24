import 'dart:async';
import 'dart:convert';

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../../constants/enum.dart';
import '../../../../../../../global_providers/global_providers.dart';
import '../../../../../../../graphql/__generated__/schema.graphql.dart';
import '../../../../../../account/data/account_permission.dart';
import '../../../../../../account/data/account_providers.dart';
import '../../../../../../auth/data/auth_coordinator.dart';
import '../../../../../../auth/data/auth_credentials_store.dart';
import '../../../../../../auth/data/auth_recovery_target.dart';
import '../../../../../../auth/data/auth_state.dart';
import '../../../../../../offline/data/background/background_download_controller_shim.dart';
import '../../../../../../offline/data/offline_server_identity_repository.dart';
import '../../credential_popup/credentials_popup.dart';
import '../../credential_popup/login_credentials_popup.dart';
import '../graphql/__generated__/sign_in.graphql.dart';
import 'sign_in_executor.dart';
import 'sign_in_repository.dart';
import 'sign_in_transition.dart';

AuthType signInMode(Enum$AuthMode mode) => switch (mode) {
  Enum$AuthMode.NONE => AuthType.none,
  Enum$AuthMode.BASIC_AUTH => AuthType.basic,
  Enum$AuthMode.SIMPLE_LOGIN => AuthType.simpleLogin,
  Enum$AuthMode.UI_LOGIN => AuthType.uiLogin,
  Enum$AuthMode.$unknown => throw StateError('Unknown server sign-in mode'),
};

Enum$AuthMode serverSignInMode(AuthType mode) => switch (mode) {
  AuthType.none => Enum$AuthMode.NONE,
  AuthType.basic => Enum$AuthMode.BASIC_AUTH,
  AuthType.simpleLogin => Enum$AuthMode.SIMPLE_LOGIN,
  AuthType.uiLogin => Enum$AuthMode.UI_LOGIN,
};

SignInValues signInValues(Fragment$SignInSettingsDto data) => SignInValues(
  mode: signInMode(data.authMode),
  username: data.authUsername,
  password: data.authPassword,
  audience: data.jwtAudience,
  accessExpiry: data.jwtTokenExpiry,
  refreshExpiry: data.jwtRefreshExpiry,
);

GraphQLClient signInClient(GraphQLClient raw, Map<String, String> headers) =>
    GraphQLClient(
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

class SignInPreflightException implements Exception {
  const SignInPreflightException(this.reason);
  final String reason;
}

class SignInActions {
  SignInActions(this.ref);
  final WidgetRef ref;

  Future<void> preflight({
    required bool accounts,
    required SignInValues before,
    required SignInValues proposed,
  }) async {
    if (!accounts) return;
    final diff = proposed.difference(before);
    if (diff.credentials ||
        (before.mode != AuthType.uiLogin &&
            proposed.mode == AuthType.uiLogin)) {
      if (proposed.username.trim().isEmpty ||
          proposed.password.trim().isEmpty) {
        throw const SignInPreflightException('credentials');
      }
    }
    if (!diff.username &&
        !(before.mode != AuthType.uiLogin &&
            proposed.mode == AuthType.uiLogin)) {
      return;
    }
    final access = ref.read(settledAccountAccessProvider);
    if (!access.allows(Enum$UserPermission.MANAGE_USERS)) {
      throw const SignInPreflightException('permission');
    }
    final repository = ref.read(accountRepositoryProvider);
    int? after;
    do {
      final page = await repository.users(
        first: 100,
        after: after,
        search: proposed.username.trim(),
      );
      if (page == null) throw const SignInPreflightException('unknown');
      if (page.nodes.any(
        (user) =>
            user.id != 1 &&
            user.username.toLowerCase() ==
                proposed.username.trim().toLowerCase(),
      )) {
        throw const SignInPreflightException('taken');
      }
      if (!page.pageInfo.hasNextPage) return;
      final next = page.pageInfo.endCursor;
      if (next == null || next == after) {
        throw const SignInPreflightException('unknown');
      }
      after = next;
    } while (true);
  }

  Future<void> save({
    required SignInValues before,
    required SignInValues proposed,
    required bool accounts,
    required bool admin,
    required bool web,
  }) async {
    final access = ref.read(settledAccountAccessProvider);
    final permissions = AccountPermissionGuard(() => access);
    permissions.require(Enum$UserPermission.MANAGE_SETTINGS);
    final raw = ref.read(unauthenticatedGraphQlClientProvider);
    final address = ref.read(currentServerAddressProvider);
    final store = ref.read(authCredentialsStoreProvider.notifier);
    final old = await ref.read(authCredentialsStoreProvider.future);
    final basic = await ref.read(credentialsProvider.future);
    final coordinator = ref.read(authCoordinatorProvider.notifier);
    final background = ref.read(backgroundDownloadControllerProvider);
    final oldMode = ref.read(authTypeKeyProvider) ?? AuthType.none;
    final oldHeaders = switch (oldMode) {
      AuthType.none => <String, String>{},
      AuthType.basic => {'Authorization': ?basic},
      AuthType.simpleLogin => old.simpleLoginCookieHeader ?? <String, String>{},
      AuthType.uiLogin => old.uiAuthorizationHeader ?? <String, String>{},
    };
    final oldClient = signInClient(raw, oldHeaders);
    final repository = SignInSettingsRepository(
      oldClient,
      permissions: permissions,
    );
    final diff = proposed.difference(before);
    final patch = Input$PartialSettingsTypeInput.fromJson({
      if (proposed.mode != before.mode)
        'authMode': serverSignInMode(proposed.mode).name,
      if (diff.username) 'authUsername': proposed.username,
      if (diff.password) 'authPassword': proposed.password,
      if (diff.audience) 'jwtAudience': proposed.audience,
      if (diff.accessExpiry) 'jwtTokenExpiry': proposed.accessExpiry,
      if (diff.refreshExpiry) 'jwtRefreshExpiry': proposed.refreshExpiry,
    });
    var effectiveUsername = before.username;
    UiLoginTokens? tokens;
    String? cookie;
    String? header;

    Future<GraphQLClient> stage(
      SignInValues values, {
      bool retry = false,
    }) async {
      Map<String, String> headers = {};
      switch (values.mode) {
        case AuthType.none:
          break;
        case AuthType.basic:
          header =
              'Basic ${base64.encode(utf8.encode('${values.username}:${values.password}'))}';
          headers = {'Authorization': header!};
        case AuthType.simpleLogin:
          cookie = await coordinator.verifySimpleCredentials(
            serverBaseUrl: address,
            username: values.username,
            password: values.password,
          );
          headers = {'Cookie': cookie!};
        case AuthType.uiLogin:
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          var delay = const Duration(milliseconds: 200);
          while (true) {
            try {
              final remaining = deadline.difference(DateTime.now());
              if (remaining <= Duration.zero) {
                throw TimeoutException('Admin sign-in timed out');
              }
              tokens = await coordinator
                  .verifyUiCredentials(
                    gqlClient: raw,
                    username: values.username,
                    password: values.password,
                  )
                  .timeout(remaining);
              break;
            } catch (_) {
              if (!retry || DateTime.now().add(delay).isAfter(deadline)) {
                rethrow;
              }
              await Future<void>.delayed(delay);
              delay = Duration(
                milliseconds: (delay.inMilliseconds * 2).clamp(200, 2000),
              );
            }
          }
          headers = {'Authorization': 'Bearer ${tokens!.accessToken}'};
      }
      return signInClient(raw, headers);
    }

    void requestSignIn(AuthType mode) {
      ref.read(authRecoveryTargetProvider.notifier).set(mode);
      ref.read(needsReauthProvider.notifier).set(true);
    }

    try {
      await background.changeIdentity(() async {
        await SignInExecutor(
          write: () async {
            final result = await repository.write(patch);
            if (result == null) throw const SignInPreflightException('unknown');
            effectiveUsername = result.authUsername;
            return signInValues(result);
          },
          read: () async {
            final data = await repository.settings();
            if (data == null) throw const SignInPreflightException('unknown');
            effectiveUsername = data.authUsername;
            return signInValues(data);
          },
          authenticate: (follow, effective) async {
            final candidate = await stage(
              effective,
              retry: follow == SignInFollowUp.retryAdmin,
            );
            final data = await SignInSettingsRepository(
              candidate,
              permissions: permissions,
            ).settings();
            if (data == null || signInMode(data.authMode) != effective.mode) {
              throw const SignInPreflightException('unknown');
            }
            if (effective.mode == AuthType.uiLogin) {
              await coordinator.adoptUiLoginTokens(
                gqlClient: raw,
                tokens: tokens!,
                forEpoch: store.serverEpoch,
                address: address,
                username: effective.username,
              );
            } else if (effective.mode == AuthType.simpleLogin) {
              await store.saveSimpleLoginCookie(cookie!);
            } else if (effective.mode == AuthType.basic) {
              await ref.read(credentialsProvider.notifier).set(header!);
            }
          },
          commit: (mode) async {
            ref.read(authTypeKeyProvider.notifier).update(mode);
            if (mode != AuthType.uiLogin) await store.clearUiLoginTokens();
            if (mode != AuthType.simpleLogin) {
              await store.clearSimpleLoginCookie();
            }
            if (mode != AuthType.basic) await store.clearBasicCredentials();
            ref.read(authUsernameProvider.notifier).update(effectiveUsername);
            ref.read(authRecoveryTargetProvider.notifier).set(null);
            ref.read(needsReauthProvider.notifier).set(false);
          },
          invalidateUi: store.clearUiLoginTokens,
          requestSignIn: requestSignIn,
        ).run(
          before: before,
          proposed: proposed,
          decide: (effective) => decideSignInTransition(
            accounts: accounts,
            currentMode: before.mode,
            finalMode: effective.mode,
            diff: effective.difference(before),
            admin: admin,
            web: web,
            hasCredentials:
                effective.username.trim().isNotEmpty &&
                effective.password.trim().isNotEmpty,
          ),
        );
      });
    } finally {
      ref.invalidate(signInSettingsProvider);
    }
  }
}
